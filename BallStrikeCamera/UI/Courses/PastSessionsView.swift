import SwiftUI

struct PastSessionsView: View {
    @EnvironmentObject var session: AuthSessionStore

    @State private var selectedFilter = "All"
    @State private var shots:         [SavedShot]       = []
    @State private var rangeSessions: [PracticeSession] = []
    @State private var simSessions:   [SimSession]      = []
    @State private var rounds:        [CourseRound]     = []

    private let filters = ["All", "Range", "Sim", "Course", "Saved Shots"]

    // MARK: - Body

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: TCTheme.sectionGap) {
                    // Header
                    TCHeaderBar(initials: userInitials) {
                        TCIconButton(icon: "magnifyingglass") {}
                        TCIconButton(icon: "slider.horizontal.3") {}
                    }

                    // Section label
                    Text("PAST SESSIONS")
                        .font(.system(size: 32, weight: .black, design: .serif))
                        .foregroundColor(TCTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TCTheme.hPad)

                    // Filter tabs
                    TCFilterTabBar(tabs: filters, selected: $selectedFilter)
                        .padding(.horizontal, TCTheme.hPad)

                    // Summary strip
                    summaryStrip
                        .padding(.horizontal, TCTheme.hPad)

                    // Session cards
                    sessionCards
                        .padding(.horizontal, TCTheme.hPad)

                    // Export card
                    exportCard
                        .padding(.horizontal, TCTheme.hPad)

                    Spacer(minLength: 140)
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Past Sessions")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.clear, for: .navigationBar)
        .task { await loadData() }
    }

    // MARK: - Summary Strip

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryItem("42", "Total Sessions")

            Rectangle()
                .fill(TCTheme.border)
                .frame(width: 1, height: 24)

            summaryItem(shots.count > 0 ? "\(shots.count)" : "356", "Saved Shots")

            Rectangle()
                .fill(TCTheme.border)
                .frame(width: 1, height: 24)

            summaryItem("152", "Avg Ball Speed")
        }
        .tcCard(padding: 14)
    }

    private func summaryItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(TCTheme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.5)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Session Cards (filtered)

    @ViewBuilder
    private var sessionCards: some View {
        VStack(spacing: 14) {
            // Range sessions
            if selectedFilter == "All" || selectedFilter == "Range" {
                if rangeSessions.isEmpty {
                    mockRangeCard
                } else {
                    ForEach(rangeSessions) { rs in
                        rangeSessionCard(rs)
                    }
                }
            }

            // Sim sessions
            if selectedFilter == "All" || selectedFilter == "Sim" {
                if simSessions.isEmpty {
                    mockSimCard
                } else {
                    ForEach(simSessions) { ss in
                        simSessionCard(ss)
                    }
                }
            }

            // Course rounds
            if selectedFilter == "All" || selectedFilter == "Course" {
                if rounds.isEmpty {
                    mockCourseCard
                } else {
                    ForEach(rounds) { r in
                        courseRoundCard(r)
                    }
                }
            }

            // Saved shots grid
            if selectedFilter == "Saved Shots" {
                savedShotsGrid
            }
        }
    }

    // MARK: - Mock Range Card

    private var mockRangeCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // Dispersion thumbnail
                TCDispersionFairwayGraphic(showRings: false)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(TCTheme.border, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Range Session · May 18")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("True Carry Range")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("76")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(TCTheme.sage)
                    Text("SHOTS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                        .tracking(1)
                }
            }

            TCDivider()

            HStack(spacing: 0) {
                sessionStat("Ball Speed", "154 mph")
                sessionStat("Carry",      "236 yds")
                sessionStat("Launch",     "13.2°")
            }

            // Saved shots inside range card
            HStack {
                Text("SAVED SHOTS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(TCTheme.gold)
                    .tracking(1.5)
                Spacer()
                Text("View All (24)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.sage)
            }

            HStack(spacing: 8) {
                TCShotThumb(clubName: "Driver",    yards: 236, isBest: true)
                TCShotThumb(clubName: "7 Iron",    yards: 172)
                TCShotThumb(clubName: "58° Wedge", yards: 78)
            }
        }
        .tcCard()
    }

    // MARK: - Mock Sim Card

    private var mockSimCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // Sim illustration thumbnail
                TCModeSimIllustration()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(TCTheme.borderGold, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Sim Session · May 17")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("Oakmont CC · GSPro")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("64")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(TCTheme.gold)
                    Text("SHOTS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                        .tracking(1)
                }
            }

            TCDivider()

            HStack(spacing: 0) {
                sessionStat("Ball Speed", "158 mph")
                sessionStat("Carry",      "241 yds")
                sessionStat("Launch",     "11.8°")
            }
        }
        .tcCard()
    }

    // MARK: - Mock Course Card

    private var mockCourseCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // Course aerial thumbnail
                TCCourseAerialThumbnail(seed: 2)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(TCTheme.border, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Round · May 16")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("Stone Ridge Golf Club")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("+4")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(TCTheme.gold)
                    Text("SCORE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                        .tracking(1)
                }
            }

            TCDivider()

            HStack(spacing: 0) {
                sessionStat("Score",     "+4")
                sessionStat("Fairways",  "8/14")
                sessionStat("Putts",     "32")
            }
        }
        .tcCard()
    }

    // MARK: - Live Session Cards

    private func rangeSessionCard(_ rs: PracticeSession) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                TCDispersionFairwayGraphic(showRings: false)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(TCTheme.border, lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text("Range Session · \(shortDate(rs.startedAt))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text(rs.selectedClubName ?? "All Clubs")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(rs.shotIds.count)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(TCTheme.sage)
                    Text("SHOTS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                        .tracking(1)
                }
            }
            TCDivider()
            HStack(spacing: 0) {
                sessionStat("Avg Ball Speed", String(format: "%.0f mph", rs.summary.avgBallSpeed))
                sessionStat("Avg Carry",      String(format: "%.0f yds", rs.summary.avgCarry))
                sessionStat("Best Carry",     String(format: "%.0f yds", rs.summary.bestCarry))
            }
        }
        .tcCard()
    }

    private func simSessionCard(_ ss: SimSession) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                TCModeSimIllustration()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(TCTheme.borderGold, lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sim Session · \(shortDate(ss.startedAt))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text(ss.provider.rawValue)
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(ss.shotIds.count)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(TCTheme.gold)
                    Text("SHOTS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                        .tracking(1)
                }
            }
        }
        .tcCard()
    }

    private func courseRoundCard(_ r: CourseRound) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                TCCourseAerialThumbnail(seed: abs(r.courseName.hashValue) % 4)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(TCTheme.border, lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text("Round · \(shortDate(r.startedAt))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text(r.courseName)
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
            }
            TCDivider()
            let diff = r.scoreSummary.totalScore - r.scoreSummary.totalPar
            HStack(spacing: 0) {
                sessionStat("Score",    diff == 0 ? "E" : diff > 0 ? "+\(diff)" : "\(diff)")
                sessionStat("Fairways", "\(r.scoreSummary.fairwaysHit)")
                sessionStat("Putts",    "\(r.scoreSummary.totalPutts)")
            }
        }
        .tcCard()
    }

    // MARK: - Saved Shots Grid

    private var savedShotsGrid: some View {
        let displayShots = Array(shots.prefix(9))
        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            if displayShots.isEmpty {
                TCShotThumb(clubName: "Driver",    yards: 238, isBest: true)
                TCShotThumb(clubName: "7 Iron",    yards: 175)
                TCShotThumb(clubName: "58° Wedge", yards: 82)
            } else {
                ForEach(displayShots) { shot in
                    TCShotThumb(
                        clubName: shot.clubName ?? "Driver",
                        yards: Int(shot.metrics.carryYards)
                    )
                }
            }
        }
    }

    // MARK: - Export Card

    private var exportCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(TCTheme.gold.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(TCTheme.gold)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Export Session")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Text("Export data or analyze offline.")
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(TCTheme.textUltraMuted)
        }
        .tcCard()
    }

    // MARK: - Helpers

    private func sessionStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(TCTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private var userInitials: String {
        let name = session.userProfile?.displayName ?? "Player"
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String((parts[0].first ?? "P")).uppercased()
                 + String((parts[1].first ?? "L")).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let uid = session.currentUser?.id else { return }
        let backend = session.backend
        async let shotList      = backend.loadShots(userId: uid)
        async let rangeList     = backend.loadRangeSessions(userId: uid)
        async let simList       = backend.loadSimSessions(userId: uid)
        async let roundList     = backend.loadCourseRounds(userId: uid)
        shots         = (try? await shotList)   ?? []
        rangeSessions = (try? await rangeList)  ?? []
        simSessions   = (try? await simList)    ?? []
        rounds        = (try? await roundList)  ?? []
    }
}
