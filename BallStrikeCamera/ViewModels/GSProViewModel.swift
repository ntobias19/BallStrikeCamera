import Foundation

@MainActor
final class GSProViewModel: ObservableObject {

    // MARK: - Persisted settings

    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "gspro_host") }
    }

    @Published var portString: String {
        didSet { UserDefaults.standard.set(portString, forKey: "gspro_port") }
    }

    // MARK: - Connection state

    @Published private(set) var connectionState: GSProConnectionState = .disconnected
    @Published private(set) var playerInfo: GSProPlayerInfo?
    @Published private(set) var statusMessage: String?

    // MARK: - Send state

    @Published private(set) var isSending = false
    @Published var lastSendFeedback: String?

    private let client = GSProClient()
    private let outputService = SimOutputService()
    private var shotNumber = 1

    var port: UInt16? {
        guard let value = UInt16(portString.trimmingCharacters(in: .whitespaces)), value >= 1 else {
            return nil
        }
        return value
    }

    var canConnect: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && port != nil
    }

    init() {
        host = UserDefaults.standard.string(forKey: "gspro_host") ?? ""
        portString = UserDefaults.standard.string(forKey: "gspro_port") ?? "\(GSProClient.defaultPort)"

        client.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in self?.connectionState = state }
        }
        client.onPlayerInfo = { [weak self] info in
            Task { @MainActor [weak self] in self?.playerInfo = info }
        }
        client.onStatusMessage = { [weak self] status in
            Task { @MainActor [weak self] in self?.statusMessage = status }
        }
    }

    // MARK: - Actions

    func connect() {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty else {
            connectionState = .failed("Enter the computer's local IP address.")
            return
        }
        guard let port else {
            connectionState = .failed("Invalid port. Enter a number between 1 and 65535.")
            return
        }
        client.connect(host: trimmedHost, port: port)
    }

    func disconnect() {
        client.disconnect()
        connectionState = .disconnected
        statusMessage = nil
    }

    func sendTestShot() async {
        var metrics = SavedShotMetrics()
        metrics.ballSpeedMph = 145
        metrics.clubSpeedMph = 96
        metrics.smashFactor = 1.51
        metrics.vlaDegrees = 13
        metrics.hlaDegrees = 0.5
        metrics.backspinRpm = 2600
        metrics.sidespinRpm = 120
        metrics.spinAxisDegrees = -1
        metrics.carryYards = 238
        metrics.totalYards = 254
        await sendMetrics(metrics, label: "Test shot")
    }

    func sendMetrics(_ metrics: SavedShotMetrics) async {
        await sendMetrics(metrics, label: "Shot")
    }

    // MARK: - Private

    private func sendMetrics(_ metrics: SavedShotMetrics, label: String) async {
        guard connectionState.isConnected else {
            lastSendFeedback = "Not connected to GSPro."
            return
        }

        isSending = true
        lastSendFeedback = nil
        defer { isSending = false }

        do {
            let packet = outputService.buildGSProPacket(metrics: metrics, shotNumber: shotNumber)
            let payload = try client.encode(packet)
            #if DEBUG
            if let text = String(data: payload, encoding: .utf8) {
                print("[GSPro] -> \(text)")
            }
            #endif
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                client.sendRaw(payload) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            shotNumber += 1
            lastSendFeedback = "\(label) sent to GSPro."
        } catch {
            lastSendFeedback = error.localizedDescription
        }

        let feedback = lastSendFeedback
        try? await Task.sleep(for: .seconds(4))
        if lastSendFeedback == feedback { lastSendFeedback = nil }
    }
}
