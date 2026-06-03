import SwiftUI
import WatchConnectivity
import WatchKit

@main
struct TrueCarryWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityStore()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .environmentObject(connectivity)
                .task {
                    connectivity.activate()
                    connectivity.send(.init(kind: .refresh))
                }
        }
    }
}

@MainActor
final class WatchConnectivityStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var appState = WatchAppState.empty
    @Published var isPhoneReachable = false
    @Published var commandMessage: String?
    @Published var isSendingCommand = false

    private var isActive = false
    private var clearMessageTask: Task<Void, Never>?

    func activate() {
        guard WCSession.isSupported(), !isActive else { return }
        isActive = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
        isPhoneReachable = session.isReachable
    }

    func send(_ command: WatchCommand) {
        guard WCSession.isSupported() else {
            showMessage("Watch connectivity is unavailable.", haptic: .failure)
            return
        }

        let session = WCSession.default
        guard session.activationState == .activated else {
            showMessage("Phone connection is not ready.", haptic: .failure)
            return
        }

        guard session.isReachable else {
            let message = command.kind == .refresh
                ? "Showing the latest phone update."
                : "Open True Carry on iPhone to control it."
            showMessage(message, haptic: command.kind == .refresh ? .click : .failure)
            return
        }

        guard let payload = try? JSONEncoder().encode(command) else {
            showMessage("Could not send command.", haptic: .failure)
            return
        }

        isSendingCommand = true
        let message = [WatchPayload.commandKey: payload]
        session.sendMessage(message) { [weak self] reply in
            Task { @MainActor in
                self?.isSendingCommand = false
                self?.handleReply(reply)
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.isSendingCommand = false
                self?.showMessage(error.localizedDescription, haptic: .failure)
            }
        }
    }

    private func handleReply(_ reply: [String: Any]) {
        guard let raw = reply[WatchPayload.resultKey] as? Data,
              let result = try? JSONDecoder().decode(WatchCommandResult.self, from: raw) else {
            showMessage(nil)
            return
        }
        showMessage(result.message, haptic: result.accepted ? .success : .failure)
    }

    private func showMessage(_ message: String?, haptic: WKHapticType? = nil) {
        clearMessageTask?.cancel()
        commandMessage = message
        if let haptic {
            WKInterfaceDevice.current().play(haptic)
        }
        guard message != nil else { return }
        clearMessageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            await MainActor.run {
                self?.commandMessage = nil
            }
        }
    }

    private func apply(_ context: [String: Any]) {
        guard let raw = context[WatchPayload.stateKey] as? Data,
              let state = try? JSONDecoder().decode(WatchAppState.self, from: raw) else { return }
        appState = state
    }

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
            if let error {
                self.showMessage(error.localizedDescription, haptic: .failure)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.apply(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.apply(message)
        }
    }
}

private enum WatchTheme {
    static let background = Color(red: 0.035, green: 0.052, blue: 0.043)
    static let surface = Color(red: 0.075, green: 0.102, blue: 0.082)
    static let surfaceRaised = Color(red: 0.105, green: 0.145, blue: 0.115)
    static let cream = Color(red: 0.940, green: 0.900, blue: 0.800)
    static let muted = Color(red: 0.700, green: 0.690, blue: 0.620)
    static let gold = Color(red: 0.780, green: 0.650, blue: 0.400)
    static let sage = Color(red: 0.530, green: 0.690, blue: 0.510)
    static let blue = Color(red: 0.430, green: 0.710, blue: 0.950)
    static let warning = Color.orange
    static let danger = Color(red: 0.900, green: 0.350, blue: 0.320)
    static let border = cream.opacity(0.12)
}

private struct WatchDashboardView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityStore

    private var activeRound: WatchCompanionRoundSnapshot? { connectivity.appState.round }
    private var activeRange: WatchCompanionRangeSnapshot? {
        guard connectivity.appState.range?.isActive == true else { return nil }
        return connectivity.appState.range
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    WatchStatusStrip(isReachable: connectivity.isPhoneReachable,
                                     updatedAt: connectivity.appState.lastUpdated,
                                     isSyncing: connectivity.isSendingCommand) {
                        connectivity.send(.init(kind: .refresh))
                    }

                    if let activeRound {
                        RoundHeroCard(round: activeRound)
                    } else if let activeRange {
                        RangeHeroCard(range: activeRange,
                                      latestShot: connectivity.appState.latestShot)
                    } else {
                        EmptyWatchState(title: "Ready",
                                        message: "Start a round or range session on iPhone.",
                                        icon: "figure.golf")
                    }

                    NavigationLink {
                        RoundDetailView()
                    } label: {
                        DashboardCard(
                            icon: "flag.fill",
                            title: "Round",
                            subtitle: activeRound?.courseName ?? "No active round",
                            value: activeRound.map { "H\($0.holeNumber)" } ?? "--",
                            accent: WatchTheme.gold,
                            isActive: activeRound != nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        RangeDetailView()
                    } label: {
                        DashboardCard(
                            icon: "scope",
                            title: "Range",
                            subtitle: rangeSubtitle,
                            value: rangeValue,
                            accent: WatchTheme.sage,
                            isActive: activeRange != nil
                        )
                    }
                    .buttonStyle(.plain)

                    if let message = connectivity.commandMessage, !message.isEmpty {
                        MessageBanner(message: message)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
            .background(WatchTheme.background)
            .navigationTitle("True Carry")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        connectivity.send(.init(kind: .refresh))
                    } label: {
                        Image(systemName: connectivity.isSendingCommand ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    }
                    .disabled(connectivity.isSendingCommand)
                }
            }
        }
    }

    private var rangeSubtitle: String {
        guard let range = connectivity.appState.range, range.isActive else { return "No active session" }
        return range.selectedClubName ?? "Club not selected"
    }

    private var rangeValue: String {
        guard let range = connectivity.appState.range, range.isActive else { return "--" }
        return "\(range.shotCount)"
    }
}

private struct WatchStatusStrip: View {
    var isReachable: Bool
    var updatedAt: Date
    var isSyncing: Bool
    var refresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isReachable ? WatchTheme.sage : WatchTheme.warning)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(isReachable ? "Phone connected" : "Last phone update")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WatchTheme.cream)
                Text(updatedAt, style: .time)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WatchTheme.muted)
            }
            Spacer()
            Button(action: refresh) {
                Image(systemName: isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(WatchTheme.surfaceRaised)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isSyncing)
        }
        .padding(10)
        .background(WatchTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(WatchTheme.border, lineWidth: 1)
        )
    }
}

private struct RoundHeroCard: View {
    var round: WatchCompanionRoundSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Hole \(round.holeNumber)", systemImage: "flag.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WatchTheme.gold)
                Spacer()
                Text(scoreToParText(round.scoreToPar))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(scoreToParColor(round.scoreToPar))
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(round.centerYards)")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(WatchTheme.cream)
                    .minimumScaleFactor(0.7)
                Text("yd")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WatchTheme.muted)
            }

            Text(round.courseName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WatchTheme.muted)
                .lineLimit(1)

            HStack(spacing: 6) {
                MetricPill(label: "Front", value: "\(round.frontYards)")
                MetricPill(label: "Back", value: "\(round.backYards)")
                MetricPill(label: "Par", value: "\(round.par)")
            }
        }
        .padding(12)
        .background(WatchTheme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(WatchTheme.gold.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct RangeHeroCard: View {
    var range: WatchCompanionRangeSnapshot
    var latestShot: WatchCompanionShotSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(range.selectedClubName ?? "Range active", systemImage: "scope")
                .font(.caption.weight(.bold))
                .foregroundStyle(WatchTheme.sage)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(range.shotCount)")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(WatchTheme.cream)
                Text("shots")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WatchTheme.muted)
            }

            if let latestShot {
                Text("Last \(latestShot.carryYards) yd carry, \(latestShot.totalYards) yd total")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WatchTheme.muted)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                MetricPill(label: "Avg", value: "\(range.averageCarryYards)")
                MetricPill(label: "Best", value: "\(range.bestCarryYards)")
                MetricPill(label: "Speed", value: "\(range.averageBallSpeedMph)")
            }
        }
        .padding(12)
        .background(WatchTheme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(WatchTheme.sage.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct DashboardCard: View {
    var icon: String
    var title: String
    var subtitle: String
    var value: String
    var accent: Color
    var isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(accent.opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(WatchTheme.cream)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(isActive ? accent : WatchTheme.muted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WatchTheme.muted.opacity(0.8))
            }
        }
        .padding(10)
        .background(WatchTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isActive ? accent.opacity(0.22) : WatchTheme.border, lineWidth: 1)
        )
    }
}

private struct RoundDetailView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityStore
    @State private var scoreDraft = 4

    private var round: WatchCompanionRoundSnapshot? { connectivity.appState.round }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let round {
                    RoundHeroCard(round: round)

                    HStack(spacing: 8) {
                        BigMetricCard(label: "Total", value: "\(round.totalScore)", accent: WatchTheme.cream)
                        BigMetricCard(label: "To Par", value: scoreToParText(round.scoreToPar), accent: scoreToParColor(round.scoreToPar))
                    }

                    VStack(spacing: 8) {
                        HStack {
                            Text("Score")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WatchTheme.muted)
                            Spacer()
                            Text("\(scoreDraft)")
                                .font(.title2.weight(.heavy))
                                .foregroundStyle(WatchTheme.cream)
                        }

                        Stepper(value: $scoreDraft, in: 1...12) {
                            EmptyView()
                        }

                        WatchActionButton(title: "Save Score", icon: "checkmark.circle.fill", accent: WatchTheme.gold) {
                            connectivity.send(.init(kind: .roundSetScore,
                                                    holeNumber: round.holeNumber,
                                                    score: scoreDraft))
                        }
                    }
                    .watchCard()

                    HStack(spacing: 8) {
                        WatchActionButton(title: "Prev", icon: "chevron.left", accent: WatchTheme.blue) {
                            connectivity.send(.init(kind: .roundPreviousHole))
                        }
                        .disabled(!round.canGoPrevious || connectivity.isSendingCommand)

                        WatchActionButton(title: "Next", icon: "chevron.right", accent: WatchTheme.blue) {
                            connectivity.send(.init(kind: .roundNextHole))
                        }
                        .disabled(!round.canGoNext || connectivity.isSendingCommand)
                    }
                } else {
                    EmptyWatchState(title: "No Round",
                                    message: "Open or resume a round on iPhone.",
                                    icon: "flag.slash")
                }

                if let message = connectivity.commandMessage, !message.isEmpty {
                    MessageBanner(message: message)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .background(WatchTheme.background)
        .navigationTitle("Round")
        .onAppear {
            resetScoreDraft()
            connectivity.send(.init(kind: .refresh))
        }
        .onChange(of: round?.holeNumber) { _ in
            resetScoreDraft()
        }
    }

    private func resetScoreDraft() {
        if let score = round?.score ?? round?.par {
            scoreDraft = score
        }
    }
}

private struct RangeDetailView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityStore

    private var range: WatchCompanionRangeSnapshot? { connectivity.appState.range }
    private var latestShot: WatchCompanionShotSnapshot? { connectivity.appState.latestShot }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let range, range.isActive {
                    RangeHeroCard(range: range, latestShot: latestShot)

                    HStack(spacing: 8) {
                        BigMetricCard(label: "Avg Carry", value: "\(range.averageCarryYards)", unit: "yd", accent: WatchTheme.sage)
                        BigMetricCard(label: "Best", value: "\(range.bestCarryYards)", unit: "yd", accent: WatchTheme.gold)
                    }

                    BigMetricCard(label: "Avg Ball Speed", value: "\(range.averageBallSpeedMph)", unit: "mph", accent: WatchTheme.blue)

                    if let latestShot {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Latest Shot")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WatchTheme.muted)
                            InlineStat(label: "Club", value: latestShot.clubName ?? "Unknown")
                            InlineStat(label: "Carry", value: "\(latestShot.carryYards) yd")
                            InlineStat(label: "Total", value: "\(latestShot.totalYards) yd")
                            InlineStat(label: "Speed", value: "\(latestShot.ballSpeedMph) mph")
                            InlineStat(label: "Smash", value: String(format: "%.2f", latestShot.smashFactor))
                        }
                        .watchCard()
                    }

                    WatchActionButton(title: "End Session", icon: "stop.fill", accent: WatchTheme.danger) {
                        connectivity.send(.init(kind: .rangeEnd))
                    }
                    .disabled(connectivity.isSendingCommand)
                } else {
                    EmptyWatchState(title: "No Range Session",
                                    message: "Start a session from Watch or iPhone.",
                                    icon: "scope")

                    WatchActionButton(title: "Start Session", icon: "play.fill", accent: WatchTheme.sage) {
                        connectivity.send(.init(kind: .rangeStart))
                    }
                    .disabled(connectivity.isSendingCommand)
                }

                if let message = connectivity.commandMessage, !message.isEmpty {
                    MessageBanner(message: message)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .background(WatchTheme.background)
        .navigationTitle("Range")
        .onAppear {
            connectivity.send(.init(kind: .rangeRefresh))
        }
    }
}

private struct BigMetricCard: View {
    var label: String
    var value: String
    var unit: String = ""
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WatchTheme.muted)
                .lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(accent)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WatchTheme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchCard()
    }
}

private struct MetricPill: View {
    var label: String
    var value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.weight(.heavy))
                .foregroundStyle(WatchTheme.cream)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(WatchTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(WatchTheme.background.opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct InlineStat: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(WatchTheme.muted)
            Spacer(minLength: 6)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(WatchTheme.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.caption)
    }
}

private struct WatchActionButton: View {
    var title: String
    var icon: String
    var accent: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(WatchTheme.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyWatchState: View {
    var title: String
    var message: String
    var icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(WatchTheme.gold)
            Text(title)
                .font(.headline)
                .foregroundStyle(WatchTheme.cream)
            Text(message)
                .font(.caption2)
                .foregroundStyle(WatchTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .watchCard()
    }
}

private struct MessageBanner: View {
    var message: String

    var body: some View {
        Text(message)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(WatchTheme.cream)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(9)
            .background(WatchTheme.gold.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension View {
    func watchCard() -> some View {
        self
            .padding(10)
            .background(WatchTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(WatchTheme.border, lineWidth: 1)
            )
    }
}

private func scoreToParText(_ value: Int) -> String {
    value == 0 ? "E" : value > 0 ? "+\(value)" : "\(value)"
}

private func scoreToParColor(_ value: Int) -> Color {
    if value < 0 { return WatchTheme.sage }
    if value == 0 { return WatchTheme.blue }
    return WatchTheme.gold
}
