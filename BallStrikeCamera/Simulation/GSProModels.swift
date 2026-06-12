import Foundation

// MARK: - Connection State

enum GSProConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .failed(let message): return message
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }
}

// MARK: - Player Info

struct GSProPlayerInfo: Equatable {
    var clubDisplayName: String?
    var handed: String?
}

// MARK: - Inbound Messages

struct GSProGenericMessage: Decodable {
    var type: String?
    var message: String?
    var status: String?
    var club: String?
    var clubName: String?
    var handed: String?
    var handedness: String?
}

// MARK: - Errors

enum GSProError: LocalizedError {
    case notConnected

    var errorDescription: String? {
        "Shot not sent - GSPro is disconnected."
    }
}
