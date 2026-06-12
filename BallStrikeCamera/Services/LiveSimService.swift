import Foundation

// Broadcasts shot data to a browser-based sim session via Supabase Realtime.
// Uses only the anon (publishable) key — never the service-role key.
@MainActor
final class LiveSimService: ObservableObject {
    @Published private(set) var sessionCode: String
    @Published private(set) var isBroadcasting = false
    @Published private(set) var lastBroadcastError: String?
    @Published private(set) var shotsSent = 0

    private let config: SupabaseConfig?

    init() {
        self.config = SupabaseConfig.load()
        self.sessionCode = LiveSimService.makeCode()
    }

    private static func makeCode() -> String {
        String(format: "%06d", Int.random(in: 0..<1_000_000))
    }

    func regenerateCode() {
        sessionCode = LiveSimService.makeCode()
        shotsSent = 0
        lastBroadcastError = nil
    }

    var simURL: URL? {
        URL(string: "https://truecarry.vercel.app/play?code=\(sessionCode)")
    }

    func broadcast(metrics: SavedShotMetrics) async {
        guard let config else {
            lastBroadcastError = "Supabase not configured — check Secrets.plist"
            return
        }

        isBroadcasting = true
        defer { isBroadcasting = false }

        let broadcastURL = config.baseURL
            .appendingPathComponent("realtime/v1/api/broadcast")

        let payload: [String: Any] = [
            "ballSpeedMph": metrics.ballSpeedMph,
            "carryYards":   metrics.carryYards,
            "totalYards":   metrics.totalYards,
            "vlaDegrees":   metrics.vlaDegrees,
            "backspinRpm":  metrics.backspinRpm,
            "sidespinRpm":  metrics.sidespinRpm,
            "hlaDegrees":   metrics.hlaDegrees,
            // sidespinRpm sign: positive = fade/slice (right for RH), negative = draw/hook (left)
            "hlaDirection": metrics.sidespinRpm >= 0 ? "right" : "left",
            "smashFactor":  metrics.smashFactor,
        ]

        let body: [String: Any] = [
            "messages": [[
                "topic":   "tc-sim-\(sessionCode)",
                "event":   "shot",
                "payload": payload,
            ]],
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var req = URLRequest(url: broadcastURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        let token = UserDefaults.standard.string(forKey: "sb_access_token") ?? config.anonKey
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = bodyData

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                lastBroadcastError = "Broadcast failed (HTTP \(http.statusCode))"
            } else {
                lastBroadcastError = nil
                shotsSent += 1
            }
        } catch {
            lastBroadcastError = error.localizedDescription
        }
    }
}
