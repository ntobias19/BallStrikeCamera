import SwiftUI

struct TrueCarryInsightsView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var selectedClub = "All"
    private let clubs = ["All","Driver","3W","5I","6I","7I","8I","9I","PW"]

    private struct ClubRow: Identifiable {
        let id = UUID()
        let name: String; let carry: Int; let smash: Double; let fraction: CGFloat
    }
    private let rows: [ClubRow] = [
        .init(name: "Driver", carry: 241, smash: 1.42, fraction: 1.00),
        .init(name: "3 Wood", carry: 218, smash: 1.44, fraction: 0.90),
        .init(name: "5 Iron", carry: 191, smash: 1.43, fraction: 0.79),
        .init(name: "6 Iron", carry: 178, smash: 1.43, fraction: 0.74),
        .init(name: "7 Iron", carry: 162, smash: 1.44, fraction: 0.67),
        .init(name: "8 Iron", carry: 148, smash: 1.43, fraction: 0.61),
        .init(name: "9 Iron", carry: 132, smash: 1.42, fraction: 0.55),
        .init(name: "PW",     carry: 112, smash: 1.41, fraction: 0.46),
    ]

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: TCTheme.sectionGap) {
                    headerSection
                    clubFilterRow
                    heroStats
                    clubDistancesCard
                    dispersionCard
                    insightsCard
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 8)
            }
        }
        .navigationBarHidden(true)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Insights")
                .font(.system(size: 32, weight: .black))
                .foregroundColor(TCTheme.textPrimary)
            Text("Your performance analytics.")
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var clubFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(clubs, id: \.self) { c in
                    Button { selectedClub = c } label: {
                        Text(c)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(selectedClub == c ? .black : TCTheme.textMuted)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(selectedClub == c ? TCTheme.goldGradient : LinearGradient(colors: [TCTheme.panel], startPoint: .leading, endPoint: .trailing))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var heroStats: some View {
        HStack(spacing: 10) {
            TCMetricTile(label: "AVG CARRY", value: "162", unit: "yd", accent: TCTheme.cyan)
            TCMetricTile(label: "BALL SPEED", value: "112", unit: "mph", accent: TCTheme.gold)
            TCMetricTile(label: "SMASH", value: "1.44", unit: "", accent: TCTheme.sage)
        }
    }

    private var clubDistancesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            TCSectionHeader(title: "Club Distances")
            VStack(spacing: 10) {
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        Text(row.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(TCTheme.textSecondary)
                            .frame(width: 64, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4).fill(TCTheme.panel).frame(height: 8)
                                RoundedRectangle(cornerRadius: 4).fill(TCTheme.goldGradient)
                                    .frame(width: g.size.width * row.fraction, height: 8)
                            }
                        }
                        .frame(height: 8)
                        Text("\(row.carry) yd")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(TCTheme.textPrimary)
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            }
        }
        .tcCard()
    }

    private var dispersionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TCSectionHeader(title: "Dispersion")
            HStack(spacing: 10) {
                TCMetricTile(label: "LEFT/RIGHT", value: "±9", unit: "yd", accent: TCTheme.cyan)
                TCMetricTile(label: "LONG/SHORT", value: "±12", unit: "yd", accent: TCTheme.gold)
                TCMetricTile(label: "SHOTS", value: "48", unit: "", accent: TCTheme.sage)
            }
        }
    }

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TCSectionHeader(title: "AI Insights")
            VStack(spacing: 10) {
                insightRow("arrow.up.right.circle.fill",
                           "Driver carry improved +4 yd this week. Smash factor trending higher.",
                           TCTheme.sage)
                insightRow("scope",
                           "Dispersion tightened to ±9 yd — down from ±13 yd last month.",
                           TCTheme.cyan)
                insightRow("exclamationmark.triangle.fill",
                           "Club path averaging 2.1° in-to-out. Slight draw bias detected.",
                           TCTheme.gold)
            }
        }
        .tcCard()
    }

    private func insightRow(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundColor(color)
                .frame(width: 20)
            Text(text).font(.system(size: 13)).foregroundColor(TCTheme.textSecondary).lineSpacing(2)
        }
    }
}
