import Foundation

// MARK: - Platform Seams
//
// Architecture-only protocols that future capabilities will satisfy. Concrete
// implementations live elsewhere (or don't exist yet). Importing this file gives
// every layer of the app a stable surface to compile against while we evolve.
//
// Convention: every seam protocol has an obvious noop default so unit tests and
// release builds work without the optional component wired up.

// MARK: - Caddie

/// Recommends a club / target given the shot context. Replaceable by a heuristic engine,
/// the future AI caddie, or a remote service.
protocol CaddieAdvisor {
    func recommend(for context: CaddieContext) async -> CaddieRecommendation?
}

struct CaddieContext {
    let userId: UUID
    let distanceToPinYds: Int
    let lie: ShotLie
    let elevationChangeYds: Double?
    let windHeadingDegrees: Double?
    let windSpeedMph: Double?
    let clubAnalytics: [ShotClub.ClubCategory: ClubAnalytics]
}

struct CaddieRecommendation {
    let club: ShotClub.ClubCategory
    let confidence: Double
    let rationale: String
}

/// Default no-op advisor.
struct NoOpCaddieAdvisor: CaddieAdvisor {
    func recommend(for _: CaddieContext) async -> CaddieRecommendation? { nil }
}

// MARK: - Live Round Channel (multiplayer / leaderboards)

/// Pushes round state to peers. A real implementation will sit on Supabase Realtime,
/// MultipeerConnectivity, or a custom WebSocket — the seam stays the same.
protocol LiveRoundChannel {
    func publish(_ event: LiveRoundEvent) async
    func subscribe(roundId: UUID, onEvent: @escaping (LiveRoundEvent) -> Void)
    func unsubscribe(roundId: UUID)
}

enum LiveRoundEvent: Codable, Hashable {
    case holeScored(userId: UUID, hole: Int, score: Int)
    case shotTracked(userId: UUID, hole: Int, distanceYds: Int)
    case roundFinished(userId: UUID, totalScore: Int)
    case heartbeat(userId: UUID)
}

struct NoOpLiveRoundChannel: LiveRoundChannel {
    func publish(_: LiveRoundEvent) async {}
    func subscribe(roundId _: UUID, onEvent _: @escaping (LiveRoundEvent) -> Void) {}
    func unsubscribe(roundId _: UUID) {}
}

// MARK: - Watch Connectivity

/// Mirrors essential round state to a paired Watch app. Concrete impl will use WCSession.
protocol WatchConnectivity {
    /// Push a fresh snapshot to the watch. The snapshot is intentionally small.
    func mirror(_ snapshot: WatchRoundSnapshot) async
}

struct WatchRoundSnapshot: Codable {
    let courseName: String
    let holeNumber: Int
    let par: Int
    let yardageToCenter: Int?
    let scoreToPar: Int
    let shotCountThisHole: Int
}

struct NoOpWatchConnectivity: WatchConnectivity {
    func mirror(_: WatchRoundSnapshot) async {}
}

// MARK: - Launch Monitor Integration

/// Receives swing data from external launch monitors (Garmin R10, Mevo+, FlightScope Mevo …).
/// Implementations bridge BLE / cloud APIs into `SavedShot`.
protocol LaunchMonitorProvider {
    var displayName: String { get }
    func startSession() async throws
    func stopSession() async
    /// Asynchronous stream of incoming launch-monitor captures.
    func shotStream() -> AsyncStream<SavedShot>
}

// MARK: - Crowd-sourced Geometry

/// User-submitted geometry corrections (e.g., wrong hole order, missing bunker). The
/// real implementation will upload to Supabase + an OSM contributor account.
protocol GeometryReportSink {
    func report(_ correction: GeometryCorrection) async throws
}

struct GeometryCorrection: Codable {
    enum Kind: String, Codable {
        case wrongHoleNumber, missingFeature, misclassifiedLie, polygonError, other
    }
    var courseId: String
    var holeNumber: Int?
    var kind: Kind
    var note: String
    var coordinate: Coordinate?
    var submittedAt: Date = Date()
}

struct NoOpGeometryReportSink: GeometryReportSink {
    func report(_: GeometryCorrection) async throws {}
}

// MARK: - Seam Registry

/// Centralized default-implementations. Tests and previews replace these by assigning
/// to the corresponding static var. Avoids tangling the rest of the app with optional
/// dependency-injection plumbing for capabilities that aren't shipping yet.
enum PlatformSeams {
    nonisolated(unsafe) static var caddie:        CaddieAdvisor       = NoOpCaddieAdvisor()
    nonisolated(unsafe) static var liveChannel:   LiveRoundChannel    = NoOpLiveRoundChannel()
    nonisolated(unsafe) static var watch:         WatchConnectivity   = NoOpWatchConnectivity()
    nonisolated(unsafe) static var geometryReport: GeometryReportSink = NoOpGeometryReportSink()
}
