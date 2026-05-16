import SwiftUI

struct PastSessionsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AuthSessionStore

    private struct MockSession: Identifiable {
        let id = UUID()
        let icon: String
        let mode: String
        let detail: String
        let stat: String
        let statLabel: String
        let accent: Color
    }

    private let sessions: [MockSession] = [
        MockSession(icon: "target",     mode: "Range Session",  detail: "7 Iron · 22 shots · Today",        stat: "162", statLabel: "avg carry yd", accent: TCTheme.cyan),
        MockSession(icon: "flag.fill",  mode: "Course Round",   detail: "Pebble Beach · 9 holes · Yesterday", stat: "+3",  statLabel: "score",       accent: TCTheme.sage),
        MockSession(icon: "display",    mode: "Sim Session",    detail: "GSPro · 14 shots · 2d ago",         stat: "241", statLabel: "avg carry yd", accent: TCTheme.gold),
        MockSession(icon: "target",     mode: "Range Session",  detail: "Driver · 18 shots · 3d ago",        stat: "238", statLabel: "avg carry yd", accent: TCTheme.cyan),
        MockSession(icon: "flag.fill",  mode: "Course Round",   detail: "Augusta · 18 holes · Last week",    stat: "E",   statLabel: "score",       accent: TCTheme.sage),
        MockSession(icon: "display",    mode: "Sim Session",    detail: "OGS · 8 shots · Last week",         stat: "218", statLabel: "avg carry yd", accent: TCTheme.gold),
    ]

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(sessions) { s in
                        TCSessionCard(
                            icon: s.icon,
                            mode: s.mode,
                            detail: s.detail,
                            stat: s.stat,
                            statLabel: s.statLabel,
                            accent: s.accent
                        )
                    }
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Past Sessions")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.clear, for: .navigationBar)
    }
}
