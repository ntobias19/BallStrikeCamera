import SwiftUI

struct TrueCarryLockerView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var showClubs    = false
    @State private var showSessions = false
    @State private var clubs: [UserClub]     = []
    @State private var shots: [SavedShot]    = []
    @State private var rounds: [CourseRound] = []

    private var profile: UserProfile? { session.userProfile }
    private var user: AppUser?        { session.currentUser }

    // MARK: - Derived helpers

    private var userInitials: String {
        let name = profile?.displayName ?? user?.name ?? "G"
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2, let f = parts[0].first, let l = parts[1].first {
            return "\(f)\(l)"
        }
        return String(name.prefix(2)).uppercased()
    }

    private var displayName: String {
        profile?.displayName ?? user?.name ?? "Golfer"
    }

    private var homeCourseName: String {
        let name = profile?.homeCourseName ?? ""
        return name.isEmpty ? "No home course set" : name
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    TCHeaderBar(initials: userInitials) {
                        TCBellButton(badgeCount: 2) {}
                        TCIconButton(icon: "gearshape.fill") {}
                    }
                    VStack(spacing: TCTheme.sectionGap) {
                        profileCard
                        clubsInBagCard
                        milestonesCard
                        notesCard
                        savedShotsCard
                        settingsRowCard
                        signOutButton
                        Spacer(minLength: 140)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 8)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showClubs) {
            if let uid = user?.id {
                NavigationStack {
                    ClubsInBagView(userId: uid, backend: session.backend)
                }
                .preferredColorScheme(.dark)
            }
        }
        .sheet(isPresented: $showSessions) {
            NavigationStack { PastSessionsView() }
                .preferredColorScheme(.dark)
        }
        .task {
            if let uid = user?.id {
                async let c = try? await session.backend.loadClubs(userId: uid)
                async let s = try? await session.backend.loadShots(userId: uid)
                async let r = try? await session.backend.loadCourseRounds(userId: uid)
                clubs  = await c ?? []
                shots  = await s ?? []
                rounds = await r ?? []
            }
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        HStack(spacing: 16) {
            // Avatar with premium gold ring
            ZStack {
                Circle()
                    .fill(TCTheme.panelRaised)
                    .frame(width: 76, height: 76)
                Circle()
                    .strokeBorder(TCTheme.goldGradient, lineWidth: 3)
                    .frame(width: 76, height: 76)
                Text(String(userInitials.prefix(2)).uppercased())
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(TCTheme.gold)
            }
            .shadow(color: TCTheme.gold.opacity(0.35), radius: 14)

            VStack(alignment: .leading, spacing: 8) {
                Text(displayName)
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundColor(TCTheme.textPrimary)

                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10))
                        .foregroundColor(TCTheme.sage)
                    Text(homeCourseName)
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }

                Spacer(minLength: 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        statBadge("HANDICAP", "6.2", "Index", TCTheme.gold)
                        statBadge("ROUNDS", rounds.isEmpty ? "28" : "\(rounds.count)", "This Year", TCTheme.sage)
                        statBadge("AVG SCORE", "75.4", "Last 20", TCTheme.cyan)
                    }
                    .padding(.horizontal, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .tcCard()
    }

    private func statBadge(_ label: String, _ value: String, _ sub: String, _ color: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(color)
            Text(sub)
                .font(.system(size: 9))
                .foregroundColor(TCTheme.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Clubs in Bag Card

    private var clubsInBagCard: some View {
        VStack(spacing: 0) {
            HStack {
                TCSectionHeader(title: "Clubs in Bag")
                Button {
                    showClubs = true
                } label: {
                    Text("Manage Bag ›")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(TCTheme.gold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(TCTheme.gold.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(TCTheme.gold.opacity(0.30), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            TCDivider()
                .padding(.top, 8)

            HStack(spacing: 16) {
                // Premium golf bag illustration
                TCGolfBagIllustration()
                    .frame(width: 72, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(TCTheme.border, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    let driverName  = clubs.first(where: { $0.type == .driver })?.name ?? "Titleist TSR3 10°"
                    let fwName      = clubs.first(where: { $0.type == .fairwayWood })?.name ?? "TaylorMade Qi10 15°"
                    let ironName    = clubs.filter({ $0.type == .iron }).isEmpty ? "Titleist T200" : "Irons"
                    let wedgeName   = clubs.first(where: { $0.type == .wedge })?.name ?? "Vokey SM9 48/54/58"
                    let putterName  = clubs.first(where: { $0.type == .putter })?.name ?? "Scotty Cameron Phantom"

                    TCClubRow(category: "DRIVER", name: driverName)
                    TCClubRow(category: "3 WOOD",  name: fwName)
                    TCClubRow(category: "5-PW",    name: ironName)
                    TCClubRow(category: "WEDGES",  name: wedgeName)
                    TCClubRow(category: "PUTTER",  name: putterName)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
        }
        .tcCard()
    }

    // MARK: - Milestones Card

    private var milestonesCard: some View {
        VStack(spacing: 12) {
            TCSectionHeader(title: "Milestones")
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                TCMilestoneBadge(icon: "checkmark.seal.fill", value: "28",  label: "Rounds\nCompleted")
                TCMilestoneBadge(icon: "flame.fill",          value: "5",   label: "Sub-80\nRounds")
                TCMilestoneBadge(icon: "star.fill",           value: "74",  label: "Best\nRound")
                TCMilestoneBadge(icon: "arrow.up.right",      value: "3",   label: "Par or Better\nStreak")
            }
        }
        .tcCard()
    }

    // MARK: - Notes Card

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Notes")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Spacer()
                Button {} label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundColor(TCTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            Text("Working on a more consistent draw with driver. Focus on tempo and release.")
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textSecondary)
                .lineSpacing(3)
            Text("Updated May 14")
                .font(.system(size: 11))
                .foregroundColor(TCTheme.textMuted)
        }
        .tcCard()
    }

    // MARK: - Saved Shots Card

    private var savedShotsCard: some View {
        VStack(spacing: 12) {
            TCSectionHeader(title: "Saved Shots", viewAllAction: { showSessions = true })
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if shots.isEmpty {
                        TCShotThumb(clubName: "Driver", yards: 285, isBest: true)
                        TCShotThumb(clubName: "7 Iron", yards: 172)
                        TCShotThumb(clubName: "58°",    yards: 78)
                    } else {
                        let displayShots = Array(shots.prefix(3))
                        ForEach(Array(displayShots.enumerated()), id: \.offset) { index, shot in
                            TCShotThumb(
                                clubName: shot.clubName ?? "Club",
                                yards: Int(shot.metrics.carryYards),
                                isBest: index == 0
                            )
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .tcCard()
    }

    // MARK: - Settings Row Card

    private var settingsRowCard: some View {
        Button {} label: {
            TCSettingsRow(
                icon: "gearshape.fill",
                title: "Settings",
                value: "Preferences, units & privacy",
                accent: TCTheme.gold
            )
        }
        .buttonStyle(.plain)
        .tcCard(padding: 0)
    }

    // MARK: - Sign Out

    private var signOutButton: some View {
        Button {
            Task { await session.signOut() }
        } label: {
            Text("Sign Out")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(TCTheme.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(TCTheme.danger.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(TCTheme.danger.opacity(0.30), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}
