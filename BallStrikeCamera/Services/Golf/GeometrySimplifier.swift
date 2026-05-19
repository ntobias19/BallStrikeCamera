import Foundation
import CoreLocation

// MARK: - Geometry Simplifier

/// Decimates polygon rings using a Douglas–Peucker-style perpendicular-distance filter
/// converted to meters via an equirectangular projection. Tuned for golf-scale features
/// (10–200m) where sub-meter precision is irrelevant.
enum GeometrySimplifier {

    /// Default tolerance in meters. ~1.5 m keeps green/fairway outlines visually clean
    /// while cutting most vertex counts by 60–80 %.
    static let defaultToleranceMeters: Double = 1.5

    /// Returns a simplified copy of `ring`. The first/last vertices are preserved.
    static func simplify(_ ring: PolygonRing,
                          toleranceMeters: Double = defaultToleranceMeters) -> PolygonRing {
        guard ring.coordinates.count > 4 else { return ring }
        let simplified = douglasPeucker(ring.coordinates, tolerance: toleranceMeters)
        return PolygonRing(coordinates: simplified)
    }

    /// Bulk-simplify every polygon attached to a hole. Returns a copy of the hole with
    /// reduced vertex counts; original hole is unchanged.
    static func simplify(_ hole: GolfHole,
                          toleranceMeters: Double = defaultToleranceMeters) -> GolfHole {
        var h = hole
        if let g = h.greenPolygon   { h.greenPolygon   = simplify(g, toleranceMeters: toleranceMeters) }
        if let f = h.fairwayPolygon { h.fairwayPolygon = simplify(f, toleranceMeters: toleranceMeters) }
        h.bunkerPolygons = h.bunkerPolygons.map { simplify($0, toleranceMeters: toleranceMeters) }
        h.waterPolygons  = h.waterPolygons.map  { simplify($0, toleranceMeters: toleranceMeters) }
        return h
    }

    // MARK: - Douglas–Peucker

    private static func douglasPeucker(_ points: [Coordinate],
                                        tolerance: Double) -> [Coordinate] {
        guard points.count > 2 else { return points }
        var keep = Array(repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        recurse(points, startIndex: 0, endIndex: points.count - 1,
                tolerance: tolerance, keep: &keep)
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    private static func recurse(_ pts: [Coordinate],
                                 startIndex: Int, endIndex: Int,
                                 tolerance: Double,
                                 keep: inout [Bool]) {
        guard endIndex > startIndex + 1 else { return }
        var maxDist = 0.0
        var maxIdx  = startIndex + 1
        let a = pts[startIndex]
        let b = pts[endIndex]
        for i in (startIndex + 1)..<endIndex {
            let d = perpendicularDistanceMeters(point: pts[i], lineStart: a, lineEnd: b)
            if d > maxDist { maxDist = d; maxIdx = i }
        }
        if maxDist > tolerance {
            keep[maxIdx] = true
            recurse(pts, startIndex: startIndex, endIndex: maxIdx,
                    tolerance: tolerance, keep: &keep)
            recurse(pts, startIndex: maxIdx, endIndex: endIndex,
                    tolerance: tolerance, keep: &keep)
        }
    }

    /// Perpendicular distance from `point` to line `start`–`end`, in meters.
    /// Uses equirectangular projection — accurate over the < 1 km spans involved here.
    private static func perpendicularDistanceMeters(point p: Coordinate,
                                                     lineStart a: Coordinate,
                                                     lineEnd b: Coordinate) -> Double {
        let mPerDegLat = 111_320.0
        let lat0 = a.latitude * .pi / 180
        let mPerDegLon = 111_320.0 * cos(lat0)

        let ax = a.longitude * mPerDegLon, ay = a.latitude * mPerDegLat
        let bx = b.longitude * mPerDegLon, by = b.latitude * mPerDegLat
        let px = p.longitude * mPerDegLon, py = p.latitude * mPerDegLat

        let dx = bx - ax, dy = by - ay
        let lenSq = dx * dx + dy * dy
        if lenSq < 1e-9 { return hypot(px - ax, py - ay) }
        // Project p onto the line, clamp to segment.
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lenSq))
        let projX = ax + t * dx
        let projY = ay + t * dy
        return hypot(px - projX, py - projY)
    }
}
