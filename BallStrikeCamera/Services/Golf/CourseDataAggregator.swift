import Foundation
import CoreLocation

// MARK: - CourseDataAggregator
//
// Multi-source course enrichment. Combines:
//   • GolfCourseAPI  → authoritative scorecard (par, handicap, per-tee yardage, tee boxes
//                       with rating/slope). No geospatial geometry.
//   • OpenStreetMap   → geometry (green/fairway/bunker/water polygons, green center/front/back
//                       coordinates, tee coordinates). Pars/yardages unreliable.
//
// The merge takes the BEST of each: accurate scorecard from GolfCourseAPI laid over real
// geometry from OSM, aligned by hole number. Either source missing degrades gracefully.
//
// Result is cached through `OSMGolfService` so `loadCached` / resume see the merged course.

final class CourseDataAggregator {

    static let shared = CourseDataAggregator()

    private let golfAPI = GolfCourseAPIProvider(userId: UUID())   // userId unused for search/detail
    // Max distance a GolfCourseAPI match may be from the discovered course coordinate.
    private let matchRadiusMeters: Double = 12_000

    // MARK: - Public API

    /// Enrich a discovered (MapKit) course stub with merged scorecard + geometry.
    /// Best-effort: never throws. Returns the richest course it can assemble.
    func enrich(_ course: GolfCourse, backend: AppBackend? = nil) async -> GolfCourse {
        let cached = OSMGolfService.shared.loadCached(courseId: course.id)
        if let cached, cached.hasTrustedGeometry {
            return cached
        }

        let sharedGeometry = await loadSharedGeometry(courseId: course.id, backend: backend)
        if let sharedGeometry, sharedGeometry.hasTrustedGeometry, isUsableCachedCourse(sharedGeometry) {
            OSMGolfService.shared.cacheMergedCourse(sharedGeometry)
            return sharedGeometry
        }

        // GolfCourseAPI scorecard is the reliable source (par/yardage/handicap) and is the
        // ONLY accurate data for courses OSM hasn't mapped. Run it in a detached task so a
        // spurious SwiftUI `.task` cancellation can't drop it. Geometry is best-effort.
        let cachedScorecard = [cached, sharedGeometry].compactMap { $0 }.first(where: isUsableCachedCourse)
        let scorecard: GolfCourse?
        if let cachedScorecard {
            scorecard = cachedScorecard
        } else {
            scorecard = await Task.detached(priority: .userInitiated) { [self] in
                await fetchScorecard(for: course)
            }.value
        }
        let geometry: GolfCourse
        if let sharedGeometry, sharedGeometry.hasTrustedGeometry {
            geometry = sharedGeometry
        } else {
            geometry = await OSMGolfService.shared.enrichBestEffort(course)
        }

        let merged = merge(base: course, osm: geometry, scorecard: scorecard)
        OSMGolfService.shared.cacheMergedCourse(merged)
        if merged.hasTrustedGeometry {
            try? await sharedGeometryBackend(preferred: backend)?.saveCourseGeometry(merged)
        } else if isUsableCachedCourse(merged) {
            try? await sharedGeometryBackend(preferred: backend)?
                .requestCourseGeometryBackfill(merged, reason: "missing_geometry")
        }
        return merged
    }

    /// Resolve the user-selected tee (chosen from generic MapKit tees) to the authoritative
    /// tee box on the enriched course, matching by name then color. Falls back sensibly.
    func resolveTeeBox(_ selected: TeeBox, in course: GolfCourse) -> TeeBox {
        guard !course.teeBoxes.isEmpty else { return selected }
        if let byName = course.teeBoxes.first(where: {
            $0.name.caseInsensitiveCompare(selected.name) == .orderedSame
        }) { return byName }
        if let byColor = course.teeBoxes.first(where: {
            $0.color.caseInsensitiveCompare(selected.color) == .orderedSame
        }) { return byColor }
        return course.teeBoxes.first ?? selected
    }

    func queueBackfill(_ course: GolfCourse,
                       backend: AppBackend?,
                       reason: String = "missing_geometry") async {
        guard isUsableCachedCourse(course) else { return }
        try? await sharedGeometryBackend(preferred: backend)?
            .requestCourseGeometryBackfill(course, reason: reason)
    }

    private func isUsableCachedCourse(_ course: GolfCourse) -> Bool {
        if course.hasTrustedGeometry { return true }
        let validHoleNumbers = course.holes.filter { $0.number > 0 }.count
        let hasScorecard = validHoleNumbers >= 9 && course.teeBoxes.contains { $0.totalYards > 0 }
        return hasScorecard
    }

    private func loadSharedGeometry(courseId: String, backend: AppBackend?) async -> GolfCourse? {
        guard let backend = sharedGeometryBackend(preferred: backend) else { return nil }
        do {
            let course = try await backend.loadCourseGeometry(courseId: courseId)
            return course?.hasTrustedGeometry == true ? course : nil
        } catch {
            #if DEBUG
            print("[Aggregator] shared course geometry failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Public course geometry should still use Supabase when the signed-in/session backend is
    /// local guest storage because Supabase anonymous auth is disabled. These course endpoints
    /// are RLS-safe with the publishable key and do not require a user session.
    private func sharedGeometryBackend(preferred backend: AppBackend?) -> AppBackend? {
        if let backend, backend is SupabaseBackendService {
            return backend
        }
        if let config = SupabaseConfig.load() {
            return SupabaseBackendService(config: config)
        }
        return backend
    }

    // MARK: - GolfCourseAPI scorecard

    private func fetchScorecard(for course: GolfCourse) async -> GolfCourse? {
        guard GolfCourseAPIConfig.isConfigured else { return nil }
        do {
            let results = try await golfAPI.searchCourses(query: course.name, near: course.coordinate)
            guard var best = bestMatch(results, to: course) else { return nil }
            // If the search result lacks hole data, pull full detail.
            if best.holes.isEmpty {
                best = (try? await golfAPI.loadCourseDetails(courseId: best.id)) ?? best
            }
            return best.holes.isEmpty ? nil : best
        } catch {
            #if DEBUG
            print("[Aggregator] GolfCourseAPI scorecard failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Pick the closest scorecard course to the discovered coordinate, preferring ones with
    /// hole data and a name that overlaps the search term.
    private func bestMatch(_ results: [GolfCourse], to course: GolfCourse) -> GolfCourse? {
        guard !results.isEmpty else { return nil }
        let target = course.coordinate
        let scored = results.map { candidate -> (GolfCourse, Double) in
            var penalty = 0.0
            if candidate.holes.isEmpty { penalty += 5_000 }              // prefer real scorecards
            if !namesOverlap(candidate.name, course.name) { penalty += 3_000 }
            let dist: Double = {
                guard let t = target, let lat = candidate.latitude, let lon = candidate.longitude
                else { return 8_000 }                                    // unknown distance = mild penalty
                return CLLocation(latitude: t.latitude, longitude: t.longitude)
                    .distance(from: CLLocation(latitude: lat, longitude: lon))
            }()
            return (candidate, dist + penalty)
        }
        // Reject anything implausibly far unless it's the only option.
        let inRange = scored.filter { $0.1 < matchRadiusMeters }
        let pool = inRange.isEmpty ? scored : inRange
        return pool.min(by: { $0.1 < $1.1 })?.0
    }

    private func namesOverlap(_ a: String, _ b: String) -> Bool {
        let norm: (String) -> Set<String> = { s in
            Set(s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !["the", "golf", "club", "course", "links", "country"].contains($0) })
        }
        let sa = norm(a), sb = norm(b)
        return !sa.isDisjoint(with: sb)
    }

    // MARK: - Merge

    private func merge(base: GolfCourse, osm: GolfCourse, scorecard: GolfCourse?) -> GolfCourse {
        var result = osm                          // start from geometry (may equal `base` if OSM failed)

        guard let sc = scorecard, !sc.holes.isEmpty else {
            // No scorecard: keep OSM geometry as-is (or the bare stub).
            result.cachedAt = Date()
            return result
        }

        // Authoritative tee boxes (named, with rating/slope) from GolfCourseAPI.
        if !sc.teeBoxes.isEmpty { result.teeBoxes = sc.teeBoxes }

        // Align by hole number: scorecard is the source of truth for par/handicap/yardage;
        // OSM supplies geometry for that hole number when present.
        let osmByNumber = Dictionary(osm.holes.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })
        var mergedHoles: [GolfHole] = []
        for scHole in sc.holes.sorted(by: { $0.number < $1.number }) {
            if var geo = osmByNumber[scHole.number] {
                geo.par              = scHole.par
                geo.handicap         = scHole.handicap ?? geo.handicap
                if !scHole.teeYardsByTeeBox.isEmpty { geo.teeYardsByTeeBox = scHole.teeYardsByTeeBox }
                mergedHoles.append(geo)
            } else {
                // No geometry for this hole — keep the accurate scorecard hole.
                mergedHoles.append(scHole)
            }
        }
        result.holes = mergedHoles
        if result.name.isEmpty { result.name = sc.name }
        if result.hasRealGeometry {
            if result.geometryMetadata == nil || result.geometryMetadata?.state == .unknown {
                result.geometryMetadata = CourseGeometryMetadata(
                    state: .accepted,
                    confidence: 1.0,
                    source: osm.source.rawValue,
                    schemaVersion: 1,
                    generatedBy: osm.source == .openStreetMap ? "osm_overpass" : "shared_geometry",
                    validationErrors: [],
                    imagerySource: nil,
                    updatedAt: Date()
                )
            }
            result.source = .merged
        } else {
            result.source = .golfCourseAPI
        }
        result.cachedAt = Date()
        return result
    }
}

// MARK: - Course Mode Availability

struct CourseAvailabilityReport: Identifiable, Equatable {
    let id = UUID()
    let courseId: String
    let courseName: String
    let city: String
    let state: String
    let country: String
    let reasonCode: String
    let message: String
    let missingHoleNumbers: [Int]
    let scorecardHoleCount: Int
    let geometryHoleCount: Int
    let csvURL: URL
    let createdAt: Date

    var locationLabel: String {
        [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

enum CourseAvailability {
    private static let minimumHoleCount = 9

    static var unavailableCSVURL: URL {
        AppStorageManager.globalRoot
            .appendingPathComponent("courseAvailability")
            .appendingPathComponent("unavailable_courses.csv")
    }

    static func evaluateCourseMode(course: GolfCourse,
                                   teeBox: TeeBox?) -> CourseAvailabilityReport? {
        let scorecardHoles = course.holes.filter { $0.number > 0 }
        let expectedCount = expectedPlayableHoleCount(for: scorecardHoles)
        let geometryHoles = scorecardHoles.filter(isHoleGeometryPlayable)
        var missing: [Int] = []
        var validationErrors: [String] = []

        if !course.hasTrustedGeometry {
            validationErrors.append("missing_trusted_geometry")
        }

        guard scorecardHoles.count >= minimumHoleCount else {
            return report(
                course: course,
                reasonCode: "missing_scorecard",
                message: "This course does not have a complete scorecard yet, so True Carry cannot start a verified GPS round.",
                missing: Array(1...18),
                scorecardHoleCount: scorecardHoles.count,
                geometryHoleCount: geometryHoles.count
            )
        }

        guard hasAuthoritativeScorecard(scorecardHoles, teeBox: teeBox, expectedCount: expectedCount) else {
            return report(
                course: course,
                reasonCode: "missing_scorecard_yardages",
                message: "This course has map geometry, but it is missing verified tee-box yardages. True Carry is holding it until the scorecard and GPS map can be matched.",
                missing: [],
                scorecardHoleCount: scorecardHoles.count,
                geometryHoleCount: geometryHoles.count
            )
        }

        for number in 1...expectedCount {
            guard let hole = scorecardHoles.first(where: { $0.number == number }) else {
                missing.append(number)
                continue
            }
            if !isHoleGeometryPlayable(hole) {
                missing.append(number)
            }
            if let mismatch = yardageMismatch(for: hole, teeBox: teeBox) {
                validationErrors.append(mismatch)
            }
        }

        guard validationErrors.isEmpty, missing.isEmpty else {
            let code = validationErrors.first ?? "partial_geometry"
            let message: String
            if !missing.isEmpty {
                message = "This course is not available yet because verified tee, green, and route geometry is missing for \(missing.count) hole\(missing.count == 1 ? "" : "s")."
            } else {
                message = "This course map failed True Carry's yardage validation, so it is being held for review instead of showing unreliable pins."
            }
            return report(
                course: course,
                reasonCode: code,
                message: message,
                missing: missing,
                scorecardHoleCount: scorecardHoles.count,
                geometryHoleCount: geometryHoles.count
            )
        }

        return nil
    }

    static func recordUnavailable(_ report: CourseAvailabilityReport,
                                  teeBox: TeeBox?) {
        let url = unavailableCSVURL
        AppStorageManager.ensureDirectory(url.deletingLastPathComponent())
        let header = "timestamp,course_id,course_name,city,state,country,tee_name,tee_yards,reason,missing_holes,scorecard_holes,geometry_holes\n"
        let line = [
            csvDate(report.createdAt),
            report.courseId,
            report.courseName,
            report.city,
            report.state,
            report.country,
            teeBox?.name ?? "",
            teeBox?.totalYards.description ?? "",
            report.reasonCode,
            report.missingHoleNumbers.map(String.init).joined(separator: "|"),
            String(report.scorecardHoleCount),
            String(report.geometryHoleCount)
        ].map(csvEscape).joined(separator: ",") + "\n"

        if !FileManager.default.fileExists(atPath: url.path) {
            try? (header + line).data(using: .utf8)?.write(to: url, options: .atomic)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        if let data = line.data(using: .utf8) {
            handle.write(data)
        }
    }

    private static func expectedPlayableHoleCount(for holes: [GolfHole]) -> Int {
        if holes.count >= 18 { return 18 }
        if holes.count >= 9 { return 9 }
        return 18
    }

    private static func isHoleGeometryPlayable(_ hole: GolfHole) -> Bool {
        guard hole.number > 0,
              hole.teeCoordinate != nil,
              hole.greenCenterCoordinate != nil,
              let green = hole.greenPolygon?.coordinates,
              green.count >= 3 else { return false }
        return true
    }

    private static func hasAuthoritativeScorecard(_ holes: [GolfHole],
                                                  teeBox: TeeBox?,
                                                  expectedCount: Int) -> Bool {
        guard let teeBox, teeBox.totalYards > 0 else { return false }
        let yardageCount = (1...expectedCount).filter { number in
            guard let hole = holes.first(where: { $0.number == number }) else { return false }
            return (hole.teeYardsByTeeBox[teeBox.id] ?? 0) > 0
        }.count
        return yardageCount == expectedCount
    }

    private static func yardageMismatch(for hole: GolfHole,
                                        teeBox: TeeBox?) -> String? {
        guard let teeBox,
              let scorecardYards = hole.teeYardsByTeeBox[teeBox.id],
              scorecardYards > 0 else { return nil }
        let geometryYards = routeYards(for: hole) ?? hole.measuredYardage
        guard let geometryYards, geometryYards > 0 else { return nil }
        let tolerance = max(25, Int((Double(scorecardYards) * 0.08).rounded()))
        let delta = abs(scorecardYards - geometryYards)
        guard delta > tolerance else { return nil }
        return "hole_\(hole.number)_yardage_mismatch_\(geometryYards)_vs_\(scorecardYards)"
    }

    private static func routeYards(for hole: GolfHole) -> Int? {
        guard let path = hole.pathCoordinates, path.count >= 2 else { return nil }
        let meters = zip(path, path.dropFirst()).reduce(0.0) { partial, pair in
            let a = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let b = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return partial + a.distance(from: b)
        }
        return Int((meters * 1.09361).rounded())
    }

    private static func report(course: GolfCourse,
                               reasonCode: String,
                               message: String,
                               missing: [Int],
                               scorecardHoleCount: Int,
                               geometryHoleCount: Int) -> CourseAvailabilityReport {
        CourseAvailabilityReport(
            courseId: course.id,
            courseName: course.name,
            city: course.city,
            state: course.state,
            country: course.country,
            reasonCode: reasonCode,
            message: message,
            missingHoleNumbers: missing,
            scorecardHoleCount: scorecardHoleCount,
            geometryHoleCount: geometryHoleCount,
            csvURL: unavailableCSVURL,
            createdAt: Date()
        )
    }

    private static func csvDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
