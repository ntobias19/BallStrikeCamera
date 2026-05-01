import Foundation

enum CameraPhase: String, CaseIterable {
    case searching = "Searching"
    case tracking = "Tracking"
    case ready = "Ready"
    case captured = "Captured"
}

enum ShutterPreset: CaseIterable, Identifiable {
    case oneThousand
    case twoThousand
    case fourThousand
    case eightThousand

    var id: String { label }

    var label: String {
        switch self {
        case .oneThousand: return "1/1000"
        case .twoThousand: return "1/2000"
        case .fourThousand: return "1/4000"
        case .eightThousand: return "1/8000"
        }
    }

    var symbol: String {
        switch self {
        case .oneThousand: return "moon.fill"
        case .twoThousand: return "cloud.fill"
        case .fourThousand: return "sun.max.fill"
        case .eightThousand: return "sun.max.circle.fill"
        }
    }

    var denominator: Int32 {
        switch self {
        case .oneThousand: return 1_000
        case .twoThousand: return 2_000
        case .fourThousand: return 4_000
        case .eightThousand: return 8_000
        }
    }
}

struct CapturedFrame: Identifiable {
    let id = UUID()
    let image: PlatformImage
    let timestamp: TimeInterval
}
