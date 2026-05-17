import SwiftUI

struct TrueCarryHomeView: View {
    @EnvironmentObject var session: AuthSessionStore
    @EnvironmentObject var camera: CameraController
    var selectTab: (TCTab) -> Void

    @State private var shots: [SavedShot] = []
    @State private var rounds: [CourseRound] = []
    @State private var rangeSessions: [PracticeSession] = []
    @State private var showCamera = false
    @State private var showSessions = false

    // MARK: Derived helpers

    private var firstName: String {
        let name = session.userProfile?.displayName ?? session.currentUser?.name ?? "Golfer"
        return name.components(separatedBy: " ").first ?? name
    }

    private var userInitials: String {
        let name = session.userProfile?.displayName ?? session.currentUser?.name ?? "G"
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2,
           let f = parts[0].first,
           let l = parts[1].first {
            return "\(f)\(l)"
        }
        return String(name.prefix(2)).uppercased()
    }

    private var greetingPrefix: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning,"
        case 12..<17: return "Good afternoon,"
        default: return "Good evening,"
        }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    TCHeaderBar(initials: userInitials) {
                        TCBellButton(badgeCount: 3) {}
                    }
                    VStack(spacing: TCTheme.sectionGap) {
                        greetingCard
                        heroStartCard
                        activitySection
                        Spacer(minLength: 140)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 8)
                }
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showCamera) {
            RangeCameraScreen().ignoresSafeArea().statusBarHidden(true)
        }
        .sheet(isPresented: $showSessions) {
            NavigationStack {
                PastSessionsView()
            }
            .preferredColorScheme(.dark)
        }
        .task {
            if let uid = session.currentUser?.id {
                async let s = try? await session.backend.loadShots(userId: uid)
                async let r = try? await session.backend.loadCourseRounds(userId: uid)
                async let rs = try? await session.backend.loadRangeSessions(userId: uid)
                shots = await s ?? []
                rounds = await r ?? []
                rangeSessions = await rs ?? []
            }
        }
    }

    // MARK: Greeting Card

    private var greetingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingPrefix)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(TCTheme.textMuted)
                Text(firstName)
                    .font(.system(size: 42, weight: .black, design: .serif))
                    .foregroundColor(TCTheme.textPrimary)
            }

            TCDivider()

            HStack(spacing: 0) {
                TCStatGroup(
                    icon: "chart.line.uptrend.xyaxis",
                    value: "6.2",
                    label: "HANDICAP",
                    color: TCTheme.gold
                )
                Spacer()
                TCStatGroup(
                    icon: "flag.fill",
                    value: "\(rounds.isEmpty ? 28 : rounds.count)",
                    label: "ROUNDS YTD",
                    color: TCTheme.sage
                )
                Spacer()
                TCStatGroup(
                    icon: "scope",
                    value: "67%",
                    label: "ACCURACY",
                    color: TCTheme.cyan
                )
            }
        }
        .tcGlassCard()
    }

    // MARK: Hero Start Card

    private var heroStartCard: some View {
        ZStack(alignment: .bottom) {
            TCHeroRangeScene()
                .frame(maxWidth: .infinity)
                .frame(height: 240)

            // Dark gradient overlay — bottom-heavy for readability
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.clear, location: 0.0),
                    .init(color: TCTheme.background.opacity(0.45), location: 0.40),
                    .init(color: TCTheme.background.opacity(0.84), location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start a Session")
                        .font(.system(size: 30, weight: .black, design: .serif))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("Track every shot.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TCTheme.textSecondary)
                    Text("Know every yard.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TCTheme.textSecondary)
                    Text("Play your best.")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(TCTheme.gold)
                }

                Spacer()

                // Gold circular arrow button
                Button {
                    selectTab(.play)
                } label: {
                    ZStack {
                        Circle()
                            .fill(TCTheme.goldGradient)
                            .frame(width: 48, height: 48)
                            .shadow(color: TCTheme.gold.opacity(0.45), radius: 10, x: 0, y: 4)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(TCTheme.background)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            selectTab(.play)
        }
    }

    // MARK: Activity Feed

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Activity Feed")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundColor(TCTheme.textPrimary)
                Spacer()
                Button("View All") { showSessions = true }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.sage)
            }

            // Round card
            if let latestRound = rounds.first {
                TCFeedCard(
                    avatarInitials: userInitials,
                    name: session.userProfile?.displayName ?? session.currentUser?.name ?? "You",
                    mode: "Round",
                    courseName: latestRound.courseName,
                    dateStr: formattedDate(latestRound.startedAt),
                    primaryStat: scoreStr(latestRound),
                    primaryLabel: "SCORE",
                    secondaryStat: "\(latestRound.scoreSummary.fairwaysHit)",
                    secondaryLabel: "FAIRWAYS",
                    tertiaryStat: "\(latestRound.scoreSummary.totalPutts)",
                    tertiaryLabel: "PUTTS",
                    thumbnailView: AnyView(
                        TCRoundThumbnail(seed: 1)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    )
                )
            } else {
                TCFeedCard(
                    avatarInitials: userInitials,
                    name: session.userProfile?.displayName ?? session.currentUser?.name ?? "Noah T.",
                    mode: "Round",
                    courseName: "Pebble Beach GL",
                    dateStr: "May 14",
                    primaryStat: "78 (+6)",
                    primaryLabel: "SCORE",
                    secondaryStat: "7/14",
                    secondaryLabel: "FAIRWAYS",
                    tertiaryStat: "32",
                    tertiaryLabel: "PUTTS",
                    thumbnailView: AnyView(
                        TCRoundThumbnail(seed: 1)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    )
                )
            }

            // Range session card
            if let latestRange = rangeSessions.first {
                TCFeedCard(
                    avatarInitials: userInitials,
                    name: session.userProfile?.displayName ?? session.currentUser?.name ?? "You",
                    mode: "Practice",
                    courseName: latestRange.selectedClubName ?? "True Carry Range",
                    dateStr: formattedDate(latestRange.startedAt),
                    primaryStat: "\(Int(latestRange.summary.bestCarry)) yds",
                    primaryLabel: "BEST CARRY",
                    secondaryStat: "\(Int(latestRange.summary.avgBallSpeed)) mph",
                    secondaryLabel: "BALL SPEED",
                    tertiaryStat: "\(latestRange.summary.shotCount) shots",
                    tertiaryLabel: "SHOTS HIT",
                    thumbnailView: AnyView(
                        TCDispersionFairwayGraphic(showRings: false)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    )
                )
            } else {
                TCFeedCard(
                    avatarInitials: userInitials,
                    name: session.userProfile?.displayName ?? session.currentUser?.name ?? "Noah T.",
                    mode: "Practice",
                    courseName: "True Carry Range",
                    dateStr: "May 12",
                    primaryStat: "245 yds",
                    primaryLabel: "BEST CARRY",
                    secondaryStat: "154 mph",
                    secondaryLabel: "BALL SPEED",
                    tertiaryStat: "13.2°",
                    tertiaryLabel: "LAUNCH ANGLE",
                    thumbnailView: AnyView(
                        TCDispersionFairwayGraphic(showRings: false)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    )
                )
            }
        }
    }

    // MARK: Helpers

    private func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }

    private func scoreStr(_ round: CourseRound) -> String {
        let diff = round.scoreSummary.totalScore - round.scoreSummary.totalPar
        if diff == 0 { return "E" }
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }
}
