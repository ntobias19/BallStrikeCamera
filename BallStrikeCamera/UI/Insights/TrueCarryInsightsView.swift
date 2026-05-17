import SwiftUI

struct TrueCarryInsightsView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var selectedCategory = "Overview"
    @State private var shots: [SavedShot] = []
    private let categories = ["Overview", "Driving", "Approach", "Putting", "Insights"]

    // MARK: - Derived helpers

    private var userInitials: String {
        let name = session.userProfile?.displayName ?? session.currentUser?.name ?? "G"
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2, let f = parts[0].first, let l = parts[1].first {
            return "\(f)\(l)"
        }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    TCHeaderBar(initials: userInitials) {
                        TCIconButton(icon: "magnifyingglass") {}
                        TCIconButton(icon: "slider.horizontal.3") {}
                    }
                    VStack(spacing: TCTheme.sectionGap) {
                        pageTitleSection
                        TCUnderlineTabs(tabs: categories, selected: $selectedCategory)
                        dispersionHeroCard
                        metricTilesRow
                        performanceTrendCard
                        byClubCard
                        unlockInsightsCard
                        Spacer(minLength: 140)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 8)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            if let uid = session.currentUser?.id {
                shots = (try? await session.backend.loadShots(userId: uid)) ?? []
            }
        }
    }

    // MARK: - Page Title

    private var pageTitleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Insights")
                .font(.system(size: 44, weight: .black, design: .serif))
                .foregroundColor(TCTheme.textPrimary)
            Text("Your performance analytics.")
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Dispersion Hero Card

    private var dispersionHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shot Dispersion")
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundColor(TCTheme.gold)
                    Text("Driver  •  All Rounds")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                TCPill(text: "28 Rounds", color: TCTheme.gold)
            }

            // Full-width premium aerial dispersion graphic
            TCDispersionFairwayGraphic()
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(TCTheme.border, lineWidth: 1)
                )

            // Stats strip
            HStack(spacing: 0) {
                dispersionStatTile("67%", "ACCURACY", TCTheme.sage)
                Rectangle().fill(TCTheme.border).frame(width: 1, height: 36)
                dispersionStatTile("23.4 yds", "DISPERSION", TCTheme.cyan)
                Rectangle().fill(TCTheme.border).frame(width: 1, height: 36)
                dispersionStatTile("28", "ROUNDS", TCTheme.gold)
            }
        }
        .tcCard()
    }

    private func dispersionStatTile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(1.0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Metric Tiles Row

    private var metricTilesRow: some View {
        let ballSpeed: String
        let carry: String
        if shots.isEmpty {
            ballSpeed = "152"
            carry = "245"
        } else {
            let avgBallSpeed = shots.map { $0.metrics.ballSpeedMph }.reduce(0, +) / Double(shots.count)
            let avgCarry = shots.map { $0.metrics.carryYards }.reduce(0, +) / Double(shots.count)
            ballSpeed = avgBallSpeed > 0 ? "\(Int(avgBallSpeed))" : "152"
            carry = avgCarry > 0 ? "\(Int(avgCarry))" : "245"
        }
        return HStack(spacing: 8) {
            TCMetricTile(label: "BALL SPEED", value: ballSpeed, unit: "mph", accent: TCTheme.gold)
            TCMetricTile(label: "LAUNCH ANGLE", value: "12.4", unit: "°", accent: TCTheme.sage)
            TCMetricTile(label: "CARRY", value: carry, unit: "yds", accent: TCTheme.cyan)
            TCMetricTile(label: "SPIN RATE", value: "2360", unit: "rpm", accent: TCTheme.textSecondary)
        }
    }

    // MARK: - Performance Trend Card

    private var performanceTrendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TCSectionHeader(title: "Performance Trend")

            HStack {
                Text("Carry Distance (yds)")
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.gold)
                Spacer()
                ZStack {
                    Circle()
                        .fill(TCTheme.sage.opacity(0.14))
                        .frame(width: 52, height: 52)
                    Text("245 yds")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(TCTheme.sage)
                        .multilineTextAlignment(.center)
                }
            }

            TCTrendLine(
                values: [232, 238, 241, 235, 243, 245, 239, 247],
                color: TCTheme.sage
            )
            .frame(height: 60)

            HStack(spacing: 0) {
                statMini("Best", "247 yds")
                statMini("Average", "240 yds")
                statMiniColored("Change", "+12 yds", TCTheme.sage)
            }
        }
        .tcCard()
    }

    private func statMini(_ label: String, _ value: String) -> some View {
        VStack(alignment: .center, spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(TCTheme.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func statMiniColored(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .center, spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - By Club Card

    private var byClubCard: some View {
        VStack(spacing: 12) {
            TCSectionHeader(title: "By Club")
            VStack(spacing: 8) {
                TCBarRow(label: "Dr",  value: 245, maxValue: 245, color: TCTheme.gold)
                TCBarRow(label: "3W",  value: 215, maxValue: 245, color: TCTheme.gold)
                TCBarRow(label: "5W",  value: 195, maxValue: 245, color: TCTheme.gold)
                TCBarRow(label: "4i",  value: 175, maxValue: 245, color: TCTheme.gold)
                TCBarRow(label: "7i",  value: 150, maxValue: 245, color: TCTheme.sage)
                TCBarRow(label: "9i",  value: 120, maxValue: 245, color: TCTheme.sage)
                TCBarRow(label: "PW",  value: 95,  maxValue: 245, color: TCTheme.sage)
                TCBarRow(label: "SW",  value: 70,  maxValue: 245, color: TCTheme.sage)
            }
        }
        .tcCard()
    }

    // MARK: - Unlock Insights Card

    private var unlockInsightsCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(TCTheme.sage)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unlock Advanced Insights")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("Strokes gained, custom benchmarks & peer comparison")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TCPrimaryGoldButton(title: "Unlock Now", icon: nil) {}
        }
        .tcCard()
        .shadow(color: TCTheme.sage.opacity(0.14), radius: 18, x: 0, y: 0)
    }
}
