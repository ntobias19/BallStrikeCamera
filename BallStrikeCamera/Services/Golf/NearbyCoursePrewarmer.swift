import Foundation
import CoreLocation
import MapKit

/// Background warmer that pulls nearby courses from MapKit and seeds the OSM cache
/// for the top few candidates so a round can start instantly.
///
/// Usage:
///   let warmer = NearbyCoursePrewarmer()
///   warmer.warm(near: userLoc)
///   // …later, on view dismiss / mode change:
///   warmer.cancel()
@MainActor
final class NearbyCoursePrewarmer: ObservableObject {

    @Published private(set) var warmedCount = 0
    @Published private(set) var isWarming   = false

    private var task: Task<Void, Never>?
    private var alreadyWarmed: Set<String> = []
    private let maxCandidates: Int

    init(maxCandidates: Int = 3) {
        self.maxCandidates = maxCandidates
    }

    deinit { task?.cancel() }

    func cancel() {
        task?.cancel()
        task = nil
        isWarming = false
    }

    /// Kick off prewarming. Idempotent — if a warm is already running it is left alone.
    /// Honors `Task.cancelled` throughout the chain. Best-effort: no errors propagate.
    func warm(near location: CLLocationCoordinate2D, radiusMeters: Double = 60_000) {
        guard task?.isCancelled != false else { return }   // already running
        isWarming  = true
        warmedCount = 0
        task = Task(priority: .background) { [weak self] in
            guard let self else { return }
            let candidates = await self.nearbyCandidates(at: location, radius: radiusMeters)
            if Task.isCancelled { return }
            for course in candidates.prefix(self.maxCandidates) {
                if Task.isCancelled { break }
                if self.alreadyWarmed.contains(course.id) { continue }
                self.alreadyWarmed.insert(course.id)
                // Skip when fresh cache already exists.
                if OSMGolfService.shared.loadCached(courseId: course.id) != nil {
                    self.warmedCount += 1
                    continue
                }
                _ = await OSMGolfService.shared.enrichBestEffort(course)
                if Task.isCancelled { break }
                self.warmedCount += 1
            }
            self.isWarming = false
        }
    }

    // MARK: - Discovery

    /// Issue an MKLocalSearch for "golf course" near the user. Returns lightweight
    /// `GolfCourse` stubs (no geometry yet) ordered by distance.
    private func nearbyCandidates(at coord: CLLocationCoordinate2D,
                                   radius: Double) async -> [GolfCourse] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "golf course"
        request.region = MKCoordinateRegion(center: coord,
                                            latitudinalMeters: radius,
                                            longitudinalMeters: radius)
        guard let response = try? await MKLocalSearch(request: request).start() else {
            return []
        }
        let user = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let stubs = response.mapItems.compactMap { (item: MKMapItem) -> GolfCourse? in
            guard let name = item.name else { return nil }
            let c = item.placemark.coordinate
            let sid = "\(name)-\(Int(c.latitude * 1000))-\(Int(c.longitude * 1000))"
            return GolfCourse(
                id: sid,
                name: name,
                city: item.placemark.locality ?? "",
                state: item.placemark.administrativeArea ?? "",
                country: item.placemark.countryCode ?? "US",
                latitude: c.latitude,
                longitude: c.longitude,
                teeBoxes: [],
                source: .mapKit,
                cachedAt: Date()
            )
        }
        return stubs.sorted { a, b in
            let la = CLLocation(latitude: a.latitude ?? 0, longitude: a.longitude ?? 0)
            let lb = CLLocation(latitude: b.latitude ?? 0, longitude: b.longitude ?? 0)
            return user.distance(from: la) < user.distance(from: lb)
        }
    }
}
