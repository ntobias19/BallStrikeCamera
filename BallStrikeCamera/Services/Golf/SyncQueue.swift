import Foundation

// MARK: - Sync Operation

/// A persisted "intent to sync" something to the remote backend. Stored as JSON on disk so
/// it survives process termination and can be replayed when connectivity returns.
struct SyncOperation: Codable, Identifiable {
    enum Kind: String, Codable { case round, shot, feedPost }
    var id: UUID                = UUID()
    var kind: Kind
    var entityId: UUID
    var userId: UUID
    var enqueuedAt: Date        = Date()
    var attempts: Int           = 0
    var lastError: String?      = nil
}

// MARK: - Sync Queue

/// Deferred-write queue for the remote backend. Local writes (via `LocalBackendService`)
/// are always synchronous; the queue tracks the intent to push to the remote backend so
/// failures don't lose user data.
///
/// Lifecycle:
/// - `enqueue(_:)` from anywhere a remote save fails.
/// - `flush(using:)` periodically and at app launch.
/// - Operations with too many failures are kept on disk but skipped during flush; the user
///   can inspect them via a future "sync issues" screen.
///
/// Conflict resolution: last-write-wins via Supabase upsert. The queue holds the entity
/// reference, not the payload, so the most recent local state is what gets pushed.
@MainActor
final class SyncQueue: ObservableObject {

    static let shared = SyncQueue()

    @Published private(set) var pending: [SyncOperation] = []
    @Published private(set) var isFlushing = false

    private let maxAttempts = 8
    private let baseBackoff: TimeInterval = 2

    private init() {
        self.pending = loadAll()
    }

    // MARK: - Enqueue

    func enqueueRound(roundId: UUID, userId: UUID) {
        enqueue(.init(kind: .round, entityId: roundId, userId: userId))
    }

    func enqueueShot(shotId: UUID, userId: UUID) {
        enqueue(.init(kind: .shot, entityId: shotId, userId: userId))
    }

    private func enqueue(_ op: SyncOperation) {
        // Coalesce duplicates by (kind, entityId) — only the most recent matters.
        pending.removeAll { $0.kind == op.kind && $0.entityId == op.entityId }
        pending.append(op)
        persist(op)
    }

    // MARK: - Flush

    /// Replay queued operations against the supplied backend. Skips entries whose attempt
    /// count exceeds `maxAttempts` (left on disk for diagnostics).
    func flush(using backend: AppBackend) async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        var stillPending: [SyncOperation] = []
        for var op in pending {
            if op.attempts >= maxAttempts {
                stillPending.append(op); continue
            }
            do {
                try await execute(op, backend: backend)
                remove(op)                        // success — drop from disk + memory
            } catch {
                op.attempts += 1
                op.lastError = String(describing: error)
                persist(op)
                stillPending.append(op)
                // Exponential backoff between operations to be polite under outages.
                let delay = baseBackoff * pow(2, Double(min(op.attempts, 6)))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        pending = stillPending
    }

    // MARK: - Execute

    private func execute(_ op: SyncOperation, backend: AppBackend) async throws {
        switch op.kind {
        case .round:
            // Pull from local storage, push to remote.
            let dir = AppStorageManager.roundsDir(userId: op.userId)
            let url = dir.appendingPathComponent("\(op.entityId.uuidString).json")
            let round = try AppStorageManager.load(CourseRound.self, from: url)
            try await backend.saveRound(round)
        case .shot:
            let dir = AppStorageManager.shotsDir(userId: op.userId)
            let url = dir.appendingPathComponent("\(op.entityId.uuidString).json")
            let shot = try AppStorageManager.load(SavedShot.self, from: url)
            try await backend.saveShot(shot)
        case .feedPost:
            let dir = AppStorageManager.feedDir(userId: op.userId)
            let url = dir.appendingPathComponent("\(op.entityId.uuidString).json")
            let post = try AppStorageManager.load(FeedPost.self, from: url)
            try await backend.saveFeedPost(post)
        }
    }

    // MARK: - Disk persistence

    private static var queueDir: URL {
        let url = AppStorageManager.globalRoot.appendingPathComponent("syncQueue")
        AppStorageManager.ensureDirectory(url)
        return url
    }

    private func persist(_ op: SyncOperation) {
        let url = Self.queueDir.appendingPathComponent("\(op.id.uuidString).json")
        try? AppStorageManager.save(op, to: url)
    }

    private func remove(_ op: SyncOperation) {
        let url = Self.queueDir.appendingPathComponent("\(op.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    private func loadAll() -> [SyncOperation] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.queueDir, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? AppStorageManager.load(SyncOperation.self, from: $0) }
            .sorted { $0.enqueuedAt < $1.enqueuedAt }
    }
}
