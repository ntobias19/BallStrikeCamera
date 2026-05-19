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
    private static let bunkerAttachRadiusYds:  Double = 80
    private static let waterAttachRadiusYds:   Double = 120

    static func infer(classified: OSMClassified,
                      courseId: String,
                      startingTees: [TeeBox]) -> [GolfHole] {

        // Path 1 — authoritative `golf=hole` ways with par+ref tags.
        let authoritative = classified.holeWays.filter {
            $0.intTag("ref") != nil && $0.intTag("par") != nil
        }
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

        return sorted.compactMap { holeWay -> GolfHole? in
            guard let number = holeWay.intTag("ref"),
                  let par    = holeWay.intTag("par"),
                  let first  = holeWay.coordinates.first,
                  let last   = holeWay.coordinates.last else { return nil }

            // tee end = first node; green end = last node.
            let teeEnd   = first
            let greenEnd = last

            let nearestGreen = popNearest(in: &greens, to: greenEnd)
            let nearestFairway = popNearest(in: &fairways, to: ringMidpoint(holeWay) ?? teeEnd)
            let nearestTee = popNearest(in: &tees, to: teeEnd)

            let attachedBunkers = drainWithin(&bunkers,
                                              within: bunkerAttachRadiusYds,
                                              of:     holeWay.coordinates)
            let attachedWater   = drainWithin(&water,
                                              within: waterAttachRadiusYds,
                                              of:     holeWay.coordinates)

            return buildHole(courseId: courseId,
                             number: number,
                             par:    par,
                             handicap: holeWay.intTag("handicap"),
                             teeCoord: nearestTee?.centroid ?? teeEnd,
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

        // Build raw (tee, green, …) groupings.
        var pending: [Pending] = []
        while let green = greens.popLast() {
            guard let greenCenter = green.centroid else { continue }
            let nearestTee     = popNearest(in: &tees,     to: greenCenter)
            let nearestFairway = popNearest(in: &fairways, to: greenCenter)
            let attachedBunkers = drainWithin(&bunkers, within: bunkerAttachRadiusYds,
                                              of: green.coordinates)
            let attachedWater   = drainWithin(&water,   within: waterAttachRadiusYds,
                                              of: green.coordinates)
            pending.append(Pending(green: green, tee: nearestTee, fairway: nearestFairway,
                                   bunkers: attachedBunkers, water: attachedWater))
        }

        // Order holes by a greedy nearest-tee walk starting from the southernmost tee.
        let ordered = orderByNearestWalk(pending: pending)

        return ordered.enumerated().map { idx, p in
            let teeCenter = p.tee?.centroid ?? p.green.centroid!
            return buildHole(courseId: courseId,
                             number: idx + 1,
                             par:    inferPar(distanceYds: yardsBetween(p.green.centroid!, teeCenter)),
                             handicap: nil,
                             teeCoord: teeCenter,
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
            let cursor = current.green.centroid!
            let nextIdx = remaining.enumerated().min { l, r in
                let lc = l.element.tee?.centroid ?? l.element.green.centroid!
                let rc = r.element.tee?.centroid ?? r.element.green.centroid!
                return yardsBetween(cursor, lc) < yardsBetween(cursor, rc)
            }!.offset
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
                                  green: OSMWayGeometry?,
                                  fairway: OSMWayGeometry?,
                                  bunkers: [OSMWayGeometry],
                                  water:   [OSMWayGeometry],
                                  teeBoxes: [TeeBox]) -> GolfHole {

        let greenRing = green?.ring
        let greenCenter = green?.centroid ?? teeCoord
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

        var minT = Double.infinity, maxT = -Double.infinity
        var minC = coords.first!, maxC = coords.first!
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

    /// Removes from `pool` every way whose centroid is within `threshold` yards of any vertex in `near`.
    private static func drainWithin(_ pool: inout [OSMWayGeometry],
                                     within thresholdYds: Double,
                                     of near: [Coordinate]) -> [OSMWayGeometry] {
        var taken: [OSMWayGeometry] = []
        pool.removeAll { way in
            guard let c = way.centroid else { return false }
            for n in near where yardsBetween(c, n) <= thresholdYds {
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
    }
}
