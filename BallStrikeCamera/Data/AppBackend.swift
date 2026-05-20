import Foundation

// MARK: - Backend Protocol

/// Abstraction layer. Replace LocalBackendService with FirebaseBackendService / SupabaseBackendService later.
protocol AppBackend {
    // Auth
    func currentUser() async throws -> AppUser?
    func signIn(email: String, password: String) async throws -> AppUser
    func createAccount(name: String, email: String, password: String) async throws -> AppUser
    func continueAsGuest() async throws -> AppUser
    func signOut() async throws

    // Profile
    func saveUserProfile(_ profile: UserProfile) async throws
    func loadUserProfile(userId: UUID) async throws -> UserProfile?

    // Clubs — userId embedded in model
    func saveClub(_ club: UserClub) async throws
    func deleteClub(clubId: UUID, userId: UUID) async throws
    func loadClubs(userId: UUID) async throws -> [UserClub]

    // Shots — userId embedded in model
    func saveShot(_ shot: SavedShot) async throws
    func loadShots(userId: UUID) async throws -> [SavedShot]
    func deleteShot(shotId: UUID, userId: UUID) async throws

    // Range sessions — userId embedded in model
    func saveRangeSession(_ session: PracticeSession) async throws
    func deleteRangeSession(sessionId: UUID, userId: UUID) async throws
    func loadRangeSessions(userId: UUID) async throws -> [PracticeSession]

    // Sim sessions — userId embedded in model
    func saveSimSession(_ session: SimSession) async throws
    func loadSimSessions(userId: UUID) async throws -> [SimSession]

    // Course rounds — userId embedded in model
    func saveRound(_ round: CourseRound) async throws
    func loadCourseRounds(userId: UUID) async throws -> [CourseRound]

    // Shared course geometry — keyed by provider/course id, shared across users
    func saveCourseGeometry(_ course: GolfCourse) async throws
    func loadCourseGeometry(courseId: String) async throws -> GolfCourse?

    // Feed — userId embedded in model
    func saveFeedPost(_ post: FeedPost) async throws
    func deleteFeedPost(postId: UUID, userId: UUID) async throws
    func loadFeed(userId: UUID) async throws -> [FeedPost]

    // Entitlements & usage
    func loadEntitlement(userId: UUID) async throws -> UserEntitlement
    func loadUsageCounter(userId: UUID, date: String) async throws -> UsageCounter?
    func incrementUsage(userId: UUID, action: EntitlementAction) async throws
}

// MARK: - Default implementations (local fallback)

extension AppBackend {
    func loadEntitlement(userId: UUID) async throws -> UserEntitlement {
        UserEntitlement.freeTier(userId: userId)
    }
    func loadUsageCounter(userId: UUID, date: String) async throws -> UsageCounter? {
        nil
    }
    func incrementUsage(userId: UUID, action: EntitlementAction) async throws {
        // no-op for local
    }
    func saveCourseGeometry(_ course: GolfCourse) async throws {
        // no-op for local; OSMGolfService keeps the on-device cache.
    }
    func loadCourseGeometry(courseId: String) async throws -> GolfCourse? {
        nil
    }
}

// MARK: - Backend Errors

enum BackendError: LocalizedError {
    case userNotFound
    case wrongPassword
    case emailAlreadyExists
    case notAuthenticated
    case saveFailed(String)
    case loadFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .userNotFound:        return "Account not found."
        case .wrongPassword:       return "Incorrect password."
        case .emailAlreadyExists:  return "An account with this email already exists."
        case .notAuthenticated:    return "You must be signed in."
        case .saveFailed(let m):   return "Save failed: \(m)"
        case .loadFailed(let m):   return "Load failed: \(m)"
        case .networkError(let m): return "Network error: \(m)"
        }
    }
}
