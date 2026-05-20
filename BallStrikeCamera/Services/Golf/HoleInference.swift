import Foundation
import CoreLocation

// MARK: - Hole Inference

/// Builds `GolfHole`s out of raw OSM ways. Two paths:
/// 1. **Authoritative** — if OSM contains `golf=hole` ways with `ref` (hole number) and `par` tags,
///    we trust those. The way's first/last node give us a tee→green centerline and we attach the
///    nearest green / fairway / tee / bunkers to each hole.
/// 2. **Inferred MVP** — otherwise, 1 green = 1 hole. For each green we find the nearest tee polygon,
///    derive front/center/back, attach the nearest fairway and any bunkers/water within a radius.
///    Holes are then ordered spatially using a nearest-neighbor walk seeded at the southernmost tee.
enum HoleInference {

    // Distance thresholds (yards) used when attaching features to a hole.
    private static let fairwayAttachRadiusYds: Double = 60
    private static let bunkerAttachRadiusYds:  Double = 115
    private static let waterAttachRadiusYds:   Double = 135

    static func infer(classified: OSMClassified,
                      courseId: String,
                      startingTees: [TeeBox]) -> [GolfHole] {

        // Path 1 — authoritative `golf=hole` ways with a hole number (`ref`). Par is optional
        // here because the aggregator overlays accurate par from GolfCourseAPI; what we really
        // want from OSM is the correct hole NUMBER → green mapping for accurate pins.
        let authoritative = classified.holeWays.filter { $0.intTag("ref") != nil }
        if authoritative.count >= 9 {
            return buildAuthoritative(holeWays: authoritative,
                                      classified: classified,
                                      courseId: courseId,
                                      teeBoxes: startingTees)
        }

        // Path 2 — inferred from greens.
        return buildInferred(classified: classified,
                             courseId: courseId,
                             teeBoxes: startingTees)
    }

    // MARK: - Path 1: Authoritative golf=hole

    private static func buildAuthoritative(holeWays: [OSMWayGeometry],
                                           classified: OSMClassified,
                                           courseId: String,
                                           teeBoxes: [TeeBox]) -> [GolfHole] {
        let sorted = holeWays.sorted { ($0.intTag("ref") ?? 0) < ($1.intTag("ref") ?? 0) }
        var greens   = classified.greens
        var fairways = classified.fairways
        var tees     = classified.tees
        var bunkers  = classified.bunkers
        var water    = classified.water
        var pins     = classified.pins

        return sorted.compactMap { holeWay -> GolfHole? in
            guard let number = holeWay.intTag("ref"),
                  let first  = holeWay.coordinates.first,
                  let last   = holeWay.coordinates.last else { return nil }
            // Par from OSM if present; otherwise infer (aggregator overrides with GolfCourseAPI).
            let par = holeWay.intTag("par")
                   ?? inferPar(distanceYds: yardsBetween(first, last))

            // tee end = first node; green end = last node.
            let teeEnd   = first
            let greenEnd = last

            let nearestGreen = popNearest(in: &greens, to: greenEnd)
            let nearestFairway = popNearest(in: &fairways, to: ringMidpoint(holeWay) ?? teeEnd)
            let nearestTee = popNearest(in: &tees, to: teeEnd)
            let nearestPin = popNearestPoint(in: &pins,
                                             to: nearestGreen?.centroid ?? greenEnd,
                                             maxYards: 45)
            let featureAnchors = holeWay.coordinates
                + (nearestGreen?.coordinates ?? [])
                + (nearestFairway?.coordinates ?? [])
                + (nearestTee?.coordinates ?? [])

            let attachedBunkers = drainWithin(&bunkers,
                                              within: bunkerAttachRadiusYds,
                                              of:     featureAnchors)
            let attachedWater   = drainWithin(&water,
                                              within: waterAttachRadiusYds,
                                              of:     featureAnchors)

            return buildHole(courseId: courseId,
                             number: number,
                             par:    par,
                             handicap: holeWay.intTag("handicap"),
                             teeCoord: nearestTee?.centroid ?? teeEnd,
                             path:    holeWay.coordinates,
                             pinCoord: nearestPin?.coordinate,
                             green:   nearestGreen,
                             fairway: nearestFairway,
                             bunkers: attachedBunkers,
                             water:   attachedWater,
                             teeBoxes: teeBoxes)
        }
    }

    // MARK: - Path 2: Inferred (1 green = 1 hole)

    private static func buildInferred(classified: OSMClassified,
                                      courseId: String,
                                      teeBoxes: [TeeBox]) -> [GolfHole] {
        var greens    = classified.greens
        var fairways  = classified.fairways
        var tees      = classified.tees
        var bunkers   = classified.bunkers
        var water     = classified.water
        var pins      = classified.pins

        // Build raw (tee, green, …) groupings.
        var pending: [Pending] = []
        while let green = greens.popLast() {
            guard let greenCenter = green.centroid else { continue }
            let nearestTee     = popNearest(in: &tees,     to: greenCenter)
            let nearestFairway = popNearest(in: &fairways, to: greenCenter)
            let featureAnchors = green.coordinates
                + (nearestFairway?.coordinates ?? [])
                + (nearestTee?.coordinates ?? [])
            let attachedBunkers = drainWithin(&bunkers, within: bunkerAttachRadiusYds,
                                              of: featureAnchors)
            let attachedWater   = drainWithin(&water,   within: waterAttachRadiusYds,
                                              of: featureAnchors)
            let nearestPin = popNearestPoint(in: &pins,
                                             to: greenCenter,
                                             maxYards: 45)
            pending.append(Pending(green: green, tee: nearestTee, fairway: nearestFairway,
                                   bunkers: attachedBunkers, water: attachedWater,
                                   pin: nearestPin))
        }

        // Order holes by a greedy nearest-tee walk starting from the southernmost tee.
        let ordered = orderByNearestWalk(pending: pending)

        return ordered.enumerated().compactMap { idx, p in
            guard let greenCenter = p.green.centroid else { return nil }
            let teeCenter = p.tee?.centroid ?? greenCenter
            return buildHole(courseId: courseId,
                             number: idx + 1,
                             par:    inferPar(distanceYds: yardsBetween(greenCenter, teeCenter)),
                             handicap: nil,
                             teeCoord: teeCenter,
                             path:    inferredPath(tee: teeCenter,
                                                   fairway: p.fairway,
                                                   green: greenCenter),
                             pinCoord: p.pin?.coordinate,
                             green:   p.green,
                             fairway: p.fairway,
                             bunkers: p.bunkers,
                             water:   p.water,
                             teeBoxes: teeBoxes)
        }
    }

    private static func orderByNearestWalk(pending: [Pending]) -> [Pending] {
        guard !pending.isEmpty else { return [] }
        // Seed at the southernmost tee (smallest latitude).
        var remaining = pending
        let seedIdx = remaining.enumerated().min { lhs, rhs in
            (lhs.element.tee?.centroid?.latitude ?? lhs.element.green.centroid?.latitude ?? .infinity)
          < (rhs.element.tee?.centroid?.latitude ?? rhs.element.green.centroid?.latitude ?? .infinity)
        }?.offset ?? 0
        var current = remaining.remove(at: seedIdx)
        var ordered: [Pending] = [current]

        while !remaining.isEmpty {
            guard let cursor = current.green.centroid else { break }
            guard let nextIdx = remaining.enumerated().min(by: { l, r in
                let lc = l.element.tee?.centroid ?? l.element.green.centroid ?? cursor
                let rc = r.element.tee?.centroid ?? r.element.green.centroid ?? cursor
                return yardsBetween(cursor, lc) < yardsBetween(cursor, rc)
            })?.offset else { break }
            current = remaining.remove(at: nextIdx)
            ordered.append(current)
        }
        return ordered
    }

    // MARK: - Common builder

    private static func buildHole(courseId: String,
                                  number: Int,
                                  par: Int,
                                  handicap: Int?,
                                  teeCoord: Coordinate,
                                  path: [Coordinate]?,
                                  pinCoord: Coordinate?,
                                  green: OSMWayGeometry?,
                                  fairway: OSMWayGeometry?,
                                  bunkers: [OSMWayGeometry],
                                  water:   [OSMWayGeometry],
                                  teeBoxes: [TeeBox]) -> GolfHole {

        let greenRing = green?.ring
        let greenCenter = pinCoord ?? green?.centroid ?? teeCoord
        let (front, back) = greenFrontBack(green: greenRing, fromTee: teeCoord, center: greenCenter)

        // Map measured yardage onto every existing TeeBox so the in-app yardage display works.
        let measured = Int((CLLocation(latitude: teeCoord.latitude, longitude: teeCoord.longitude)
            .distance(from: CLLocation(latitude: greenCenter.latitude, longitude: greenCenter.longitude))
            * 1.09361).rounded())
        var teeYards: [String: Int] = [:]
        for tee in teeBoxes { teeYards[tee.id] = measured }

        return GolfHole(
            id: "\(courseId)-hole-\(number)",
            courseId: courseId,
            number: number,
            par: par,
            handicap: handicap,
            teeYardsByTeeBox: teeYards,
            greenFrontCoordinate:  front,
            greenCenterCoordinate: greenCenter,
            greenBackCoordinate:   back,
            teeCoordinateByTeeBox: Dictionary(uniqueKeysWithValues: teeBoxes.map { ($0.id, teeCoord) }),
            pathCoordinates: cleanedPath(path, fallback: [teeCoord, greenCenter]),
            hazards: bunkers.compactMap { hazard(from: $0, type: .bunker) }
                   + water.compactMap   { hazard(from: $0, type: .water)  },
            teeCoordinate: teeCoord,
            greenPolygon:   greenRing,
            fairwayPolygon: fairway?.ring,
            bunkerPolygons: bunkers.map { $0.ring },
            waterPolygons:  water.map   { $0.ring }
        )
    }

    private static func hazard(from way: OSMWayGeometry, type: HazardType) -> Hazard? {
        guard let c = way.centroid else { return nil }
        return Hazard(id: "osm-\(way.id)", type: type, name: way.tag("name"),
                      coordinate: c, frontCoordinate: nil, carryCoordinate: nil)
    }

    private static func inferredPath(tee: Coordinate,
                                     fairway: OSMWayGeometry?,
                                     green: Coordinate) -> [Coordinate] {
        var path = [tee]
        if let fairwayCenter = fairway?.centroid,
           yardsBetween(tee, fairwayCenter) > 35,
           yardsBetween(fairwayCenter, green) > 35 {
            path.append(fairwayCenter)
        }
        path.append(green)
        return path
    }

    private static func cleanedPath(_ path: [Coordinate]?,
                                    fallback: [Coordinate]) -> [Coordinate] {
        let source: [Coordinate]
        if let path, path.count >= 2 {
            source = path
        } else {
            source = fallback
        }
        var cleaned: [Coordinate] = []
        for coord in source {
            if let last = cleaned.last, yardsBetween(last, coord) < 3 { continue }
            cleaned.append(coord)
        }
        return cleaned.count >= 2 ? cleaned : fallback
    }

    // MARK: - Geometry helpers

    /// Front/back of green: project all green vertices onto the tee→center vector and pick min/max.
    private static func greenFrontBack(green: PolygonRing?,
                                        fromTee tee: Coordinate,
                                        center: Coordinate) -> (front: Coordinate?, back: Coordinate?) {
        guard let coords = green?.coordinates, !coords.isEmpty else { return (nil, nil) }
        // Equirectangular projection — adequate over a single green (~50m).
        let lat0 = tee.latitude * .pi / 180
        let cosLat0 = cos(lat0)
        func project(_ c: Coordinate) -> (x: Double, y: Double) {
            let x = (c.longitude - tee.longitude) * cosLat0
            let y = (c.latitude  - tee.latitude)
            return (x, y)
        }
        let centerP = project(center)
        let len = sqrt(centerP.x * centerP.x + centerP.y * centerP.y)
        guard len > 0 else { return (nil, nil) }
        let ux = centerP.x / len, uy = centerP.y / len

        guard let first = coords.first else { return (nil, nil) }
        var minT = Double.infinity, maxT = -Double.infinity
        var minC = first, maxC = first
        for c in coords {
            let p = project(c)
            let t = p.x * ux + p.y * uy
            if t < minT { minT = t; minC = c }
            if t > maxT { maxT = t; maxC = c }
        }
        return (front: minC, back: maxC)
    }

    private static func popNearest(in pool: inout [OSMWayGeometry],
                                    to point: Coordinate) -> OSMWayGeometry? {
        guard let bestIdx = pool.enumerated().min(by: {
            yardsBetween($0.element.centroid ?? point, point)
          < yardsBetween($1.element.centroid ?? point, point)
        })?.offset else { return nil }
        return pool.remove(at: bestIdx)
    }

    private static func popNearestPoint(in pool: inout [OSMPointGeometry],
                                        to point: Coordinate,
                                        maxYards: Double) -> OSMPointGeometry? {
        guard let best = pool.enumerated().min(by: {
            yardsBetween($0.element.coordinate, point)
          < yardsBetween($1.element.coordinate, point)
        }) else { return nil }
        guard yardsBetween(best.element.coordinate, point) <= maxYards else { return nil }
        return pool.remove(at: best.offset)
    }

    /// Removes from `pool` every way whose centroid is close to the active hole route.
    private static func drainWithin(_ pool: inout [OSMWayGeometry],
                                     within thresholdYds: Double,
                                     of near: [Coordinate]) -> [OSMWayGeometry] {
        var taken: [OSMWayGeometry] = []
        pool.removeAll { way in
            guard let c = way.centroid else { return false }
            if yardsFromPointToPath(c, path: near) <= thresholdYds {
                taken.append(way); return true
            }
            return false
        }
        return taken
    }

    private static func ringMidpoint(_ w: OSMWayGeometry) -> Coordinate? {
        guard !w.coordinates.isEmpty else { return nil }
        return w.coordinates[w.coordinates.count / 2]
    }

    private static func yardsBetween(_ a: Coordinate, _ b: Coordinate) -> Double {
        let la = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let lb = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return la.distance(from: lb) * 1.09361
    }

    private static func yardsFromPointToPath(_ point: Coordinate,
                                             path: [Coordinate]) -> Double {
        guard !path.isEmpty else { return .infinity }
        guard path.count >= 2 else { return yardsBetween(point, path[0]) }
        return zip(path, path.dropFirst()).map { start, end in
            yardsFromPointToSegment(point, start: start, end: end)
        }.min() ?? .infinity
    }

    private static func yardsFromPointToSegment(_ point: Coordinate,
                                                start: Coordinate,
                                                end: Coordinate) -> Double {
        let lat0 = point.latitude * .pi / 180
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(lat0)

        let px = point.longitude * metersPerDegreeLon
        let py = point.latitude * metersPerDegreeLat
        let ax = start.longitude * metersPerDegreeLon
        let ay = start.latitude * metersPerDegreeLat
        let bx = end.longitude * metersPerDegreeLon
        let by = end.latitude * metersPerDegreeLat

        let dx = bx - ax
        let dy = by - ay
        let denom = dx * dx + dy * dy
        let t = denom <= .leastNonzeroMagnitude
            ? 0
            : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / denom))
        let cx = ax + t * dx
        let cy = ay + t * dy
        let meters = hypot(px - cx, py - cy)
        return meters * 1.09361
    }

    /// Crude par inference from tee→green distance (yards). Used only in inferred mode.
    private static func inferPar(distanceYds: Double) -> Int {
        if distanceYds < 245 { return 3 }
        if distanceYds < 480 { return 4 }
        return 5
    }

    // MARK: - Nested type for the inferred path

    private struct Pending {
        let green: OSMWayGeometry
        let tee:   OSMWayGeometry?
        let fairway: OSMWayGeometry?
        let bunkers: [OSMWayGeometry]
        let water:   [OSMWayGeometry]
        let pin: OSMPointGeometry?
    }
}
