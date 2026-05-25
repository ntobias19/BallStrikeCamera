import WidgetKit
import SwiftUI

// Must match WidgetBridge.RoundWidgetData in the main app.
struct RoundWidgetData: Codable {
    var holeNumber: Int = 0
    var scoreToPar: Int = 0
    var totalScore: Int = 0
    var frontYards: Int = 0
    var centerYards: Int = 0
    var backYards: Int = 0
    var courseName: String = ""
    var hasActiveRound: Bool = false
}

struct RoundEntry: TimelineEntry {
    let date: Date
    let data: RoundWidgetData
}

struct RoundTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RoundEntry {
        RoundEntry(date: .now, data: RoundWidgetData(
            holeNumber: 7, scoreToPar: -1, totalScore: 33,
            frontYards: 128, centerYards: 143, backYards: 159,
            courseName: "Pebble Beach", hasActiveRound: true
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (RoundEntry) -> Void) {
        completion(RoundEntry(date: .now, data: readData()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RoundEntry>) -> Void) {
        let entry = RoundEntry(date: .now, data: readData())
        // .never — app drives refreshes via WidgetCenter.reloadAllTimelines()
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func readData() -> RoundWidgetData {
        guard let defaults = UserDefaults(suiteName: "group.com.noahtobias.BallStrikeCamera"),
              let raw = defaults.data(forKey: "roundWidgetData"),
              let decoded = try? JSONDecoder().decode(RoundWidgetData.self, from: raw) else {
            return RoundWidgetData()
        }
        return decoded
    }
}

// MARK: - Score label helper

private func scoreLabel(_ stp: Int) -> String {
    if stp == 0 { return "E" }
    return stp > 0 ? "+\(stp)" : "\(stp)"
}

// MARK: - Rectangular (primary lock screen widget)
// Shows: HOLE # · score-to-par   /   F · C · B distances

struct RectangularView: View {
    let data: RoundWidgetData

    var body: some View {
        if !data.hasActiveRound {
            VStack(alignment: .leading, spacing: 2) {
                Text("True Carry")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text("No active round")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetAccentable()
        } else {
            VStack(alignment: .leading, spacing: 3) {
                // Row 1: Hole + score
                HStack(spacing: 6) {
                    Text("HOLE \(data.holeNumber)")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .widgetAccentable()
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(scoreLabel(data.scoreToPar))
                        .font(.system(size: 13, weight: .black, design: .rounded))
                    Text("(\(data.totalScore))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                // Row 2: F / C / B distances
                HStack(spacing: 0) {
                    distanceChip(label: "F", yards: data.frontYards, hero: false)
                    Spacer()
                    distanceChip(label: "C", yards: data.centerYards, hero: true)
                    Spacer()
                    distanceChip(label: "B", yards: data.backYards, hero: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    func distanceChip(label: String, yards: Int, hero: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(label)
                .font(.system(size: hero ? 10 : 9, weight: .black, design: .rounded))
                .foregroundStyle(hero ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            Text("\(yards)")
                .font(.system(size: hero ? 20 : 14, weight: .black, design: .rounded))
                .foregroundStyle(hero ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .widgetAccentable(hero)
            if hero {
                Text("yd")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Circular (compact lock screen widget)
// Shows center distance, or hole number when no GPS

struct CircularView: View {
    let data: RoundWidgetData

    var body: some View {
        if !data.hasActiveRound {
            Image(systemName: "flag.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .widgetAccentable()
        } else {
            VStack(spacing: 0) {
                Text("H\(data.holeNumber)")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("\(data.centerYards)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                Text("yd")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Inline (lock screen banner text)

struct InlineView: View {
    let data: RoundWidgetData

    var body: some View {
        if !data.hasActiveRound {
            Label("No round", systemImage: "flag")
        } else {
            Label(
                "H\(data.holeNumber)  \(scoreLabel(data.scoreToPar))  \(data.centerYards)yd",
                systemImage: "flag.fill"
            )
        }
    }
}

// MARK: - Entry view dispatcher

struct RoundWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: RoundEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            RectangularView(data: entry.data)
        case .accessoryCircular:
            CircularView(data: entry.data)
        case .accessoryInline:
            InlineView(data: entry.data)
        default:
            RectangularView(data: entry.data)
        }
    }
}

// MARK: - Widget bundle (entry point for the extension)

@main
struct BallStrikeCameraWidgetBundle: WidgetBundle {
    var body: some Widget {
        BallStrikeCameraWidget()
        RoundLiveActivity()
    }
}

struct BallStrikeCameraWidget: Widget {
    let kind: String = "RoundWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RoundTimelineProvider()) { entry in
            RoundWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Round")
        .description("Hole, score, and green distances on your lock screen.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
