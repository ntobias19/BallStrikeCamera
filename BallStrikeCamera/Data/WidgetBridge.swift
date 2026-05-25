import Foundation
import WidgetKit

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

enum WidgetBridge {
    private static let suiteName = "group.com.noahtobias.BallStrikeCamera"
    private static let dataKey   = "roundWidgetData"

    static func write(_ data: RoundWidgetData) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let encoded  = try? JSONEncoder().encode(data) else { return }
        defaults.set(encoded, forKey: dataKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> RoundWidgetData {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let raw      = defaults.data(forKey: dataKey),
              let decoded  = try? JSONDecoder().decode(RoundWidgetData.self, from: raw) else {
            return RoundWidgetData()
        }
        return decoded
    }

    static func clear() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: dataKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
