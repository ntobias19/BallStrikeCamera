import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Attributes (must match ActivityBridge.swift in the main app)

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

// MARK: - Helpers

private func scoreLabel(_ stp: Int) -> String {
    stp == 0 ? "E" : stp > 0 ? "+\(stp)" : "\(stp)"
}

private func scoreColor(_ stp: Int) -> Color {
    stp < 0 ? Color(red: 0.25, green: 0.82, blue: 0.45) :
    stp > 0 ? Color(red: 1.0,  green: 0.4,  blue: 0.4)  : .white
}

// MARK: - Lock screen / notification banner view

struct RoundLockScreenView: View {
    let state: RoundActivityAttributes.ContentState

    var body: some View {
        ZStack {
            // Full-bleed logo watermark over True Carry green background
            Image("tc_logo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.12)

            // Content
            HStack(spacing: 0) {
                // Left: hole + score-to-par
                VStack(alignment: .leading, spacing: 2) {
                    Text("HOLE \(state.holeNumber)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(scoreLabel(state.scoreToPar))
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(scoreColor(state.scoreToPar))
                    Text("\(state.totalScore) total")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right: F / C / B
                VStack(alignment: .trailing, spacing: 5) {
                    distanceRow(label: "F", yards: state.frontYards, hero: false)
                    distanceRow(label: "C", yards: state.centerYards, hero: true)
                    distanceRow(label: "B", yards: state.backYards, hero: false)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 18)
        }
        .padding(.vertical, 14)
        .activityBackgroundTint(Color(red: 0.118, green: 0.165, blue: 0.133))
        .activitySystemActionForegroundColor(.white)
    }

    @ViewBuilder
    func distanceRow(label: String, yards: Int, hero: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label)
                .font(.system(size: hero ? 10 : 8, weight: .black, design: .rounded))
                .foregroundStyle(hero ? .white : .white.opacity(0.4))
                .frame(width: 10, alignment: .leading)
            Text("\(yards)")
                .font(.system(size: hero ? 28 : 15, weight: .black, design: .rounded))
                .foregroundStyle(hero ? .white : .white.opacity(0.6))
            if hero {
                Text("yd")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }
}

// MARK: - Widget

struct RoundLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RoundActivityAttributes.self) { context in
            RoundLockScreenView(state: context.state)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("HOLE \(s.holeNumber)")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(scoreLabel(s.scoreToPar))
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(scoreColor(s.scoreToPar))
                        Text("\(s.totalScore) total")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 5) {
                        expandedDistanceRow(label: "F", yards: s.frontYards, hero: false)
                        expandedDistanceRow(label: "C", yards: s.centerYards, hero: true)
                        expandedDistanceRow(label: "B", yards: s.backYards, hero: false)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        Image("tc_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 12)
                            .opacity(0.6)
                        if !s.courseName.isEmpty {
                            Text(s.courseName)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } compactLeading: {
                Text("H\(s.holeNumber)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
            } compactTrailing: {
                Text("\(s.centerYards)y")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(scoreColor(s.scoreToPar))
            } minimal: {
                Text("\(s.holeNumber)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
            }
        }
    }

    @ViewBuilder
    func expandedDistanceRow(label: String, yards: Int, hero: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(label)
                .font(.system(size: hero ? 9 : 8, weight: .black, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 10, alignment: .leading)
            Text("\(yards)")
                .font(.system(size: hero ? 20 : 13, weight: .black, design: .rounded))
            if hero {
                Text("y")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
