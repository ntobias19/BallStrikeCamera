import Foundation
import Network

/// TCP client for GSPro Connect. The UI owns this through GSProViewModel.
final class GSProClient {
    static let defaultPort: UInt16 = 921
    private static let delimiter = Data("\n".utf8)

    var onStateChange: ((GSProConnectionState) -> Void)?
    var onPlayerInfo: ((GSProPlayerInfo) -> Void)?
    var onStatusMessage: ((String) -> Void)?

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private let queue = DispatchQueue(label: "com.truecarry.gspro.tcp", qos: .userInitiated)

    // MARK: - Connect / Disconnect

    func connect(host: String, port: UInt16) {
        disconnect()
        notify(.connecting)

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            notify(.failed("Invalid port."))
            return
        }

        let conn = NWConnection(
            to: .hostPort(host: NWEndpoint.Host(host), port: nwPort),
            using: .tcp
        )
        connection = conn
        receiveBuffer = Data()

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.notify(.connected)
                self.startReceiving(conn)
            case .failed(let error):
                self.notify(.failed(self.describe(error)))
                self.connection = nil
            case .cancelled:
                self.notify(.disconnected)
                self.connection = nil
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        receiveBuffer = Data()
    }

    // MARK: - Send

    func encode(_ packet: SimOutputService.SimShotPacket) throws -> Data {
        let encoder = JSONEncoder()
        var payload = try encoder.encode(packet)
        payload.append(contentsOf: Self.delimiter)
        return payload
    }

    func sendRaw(_ payload: Data, completion: @escaping (Error?) -> Void) {
        guard let conn = connection else {
            completion(GSProError.notConnected)
            return
        }

        conn.send(content: payload, completion: .contentProcessed { error in
            DispatchQueue.main.async { completion(error) }
        })
    }

    // MARK: - Receive

    private func startReceiving(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBuffer()
            }
            if error != nil || isComplete {
                self.notify(.disconnected)
                return
            }
            self.startReceiving(conn)
        }
    }

    private func processBuffer() {
        while let range = receiveBuffer.range(of: Self.delimiter) {
            let line = receiveBuffer.subdata(in: receiveBuffer.startIndex..<range.lowerBound)
            receiveBuffer.removeSubrange(..<range.upperBound)
            guard !line.isEmpty else { continue }
            decodeMessage(line)
        }
    }

    private func decodeMessage(_ data: Data) {
        #if DEBUG
        if let text = String(data: data, encoding: .utf8) {
            print("[GSPro] <- \(text)")
        }
        #endif

        let decoder = JSONDecoder()
        guard let message = try? decoder.decode(GSProGenericMessage.self, from: data) else { return }

        if let status = message.status ?? message.message ?? message.type {
            DispatchQueue.main.async { [weak self] in self?.onStatusMessage?(status) }
        }

        let info = GSProPlayerInfo(
            clubDisplayName: message.clubDisplayName,
            handed: message.handedDisplayName
        )
        if info.clubDisplayName != nil || info.handed != nil {
            DispatchQueue.main.async { [weak self] in self?.onPlayerInfo?(info) }
        }
    }

    // MARK: - Helpers

    private func notify(_ state: GSProConnectionState) {
        DispatchQueue.main.async { [weak self] in self?.onStateChange?(state) }
    }

    private func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNREFUSED:
                return "Connection refused. Is GSPro Connect running?"
            case .ETIMEDOUT:
                return "Timed out. Check the IP address."
            case .ENETUNREACH:
                return "Network unreachable."
            default:
                return "Could not connect. Make sure GSPro is open and on the same Wi-Fi."
            }
        default:
            return "Could not connect. Make sure GSPro is open and on the same Wi-Fi."
        }
    }

    deinit { disconnect() }
}

private extension GSProGenericMessage {
    var clubDisplayName: String? {
        clubName ?? club
    }

    var handedDisplayName: String? {
        handedness ?? handed
    }
}
