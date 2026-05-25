import Foundation
import ActivityKit

// MARK: - Attributes (must match RoundLiveActivity.swift in the widget extension)

@available(iOS 16.2, *)
struct RoundActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var holeNumber: Int
        var scoreToPar: Int
        var totalScore: Int
        var frontYards: Int
        var centerYards: Int
        var backYards: Int
        var courseName: String
    }
    var courseId: String
}

// MARK: - Bridge

@available(iOS 16.2, *)
enum ActivityBridge {
    private static var currentActivity: Activity<RoundActivityAttributes>?

    static func updateOrStart(courseId: String, state: RoundActivityAttributes.ContentState) {
        if let existing = currentActivity,
           existing.activityState == .active {
            Task { await existing.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            start(courseId: courseId, state: state)
        }
    }

    static func end() {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            currentActivity = nil
        }
    }

    private static func start(courseId: String, state: RoundActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs   = RoundActivityAttributes(courseId: courseId)
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            currentActivity = try Activity.request(attributes: attrs, content: content)
        } catch {
            print("[ActivityBridge] failed to start: \(error)")
        }
    }
}
