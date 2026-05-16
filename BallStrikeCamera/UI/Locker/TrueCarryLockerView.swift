import SwiftUI

struct TrueCarryLockerView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var showClubs     = false
    @State private var showSessions  = false

    private var profile: UserProfile? { session.userProfile }
    private var user: AppUser?        { session.currentUser }

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: TCTheme.sectionGap) {
                    headerSection
                    profileCard
                    statsRow
                    savedShotsSection
                    gearSection
                    settingsSection
                    signOutButton
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 8)
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
    }

    // MARK: Header

    private var headerSection: some View {
        Text("Locker")
            .font(.system(size: 32, weight: .black))
            .foregroundColor(TCTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    // MARK: Profile Card

    private var profileCard: some View {
        HStack(spacing: 18) {
            Circle()
                .fill(TCTheme.goldGradient)
                .frame(width: 68, height: 68)
                .overlay(
                    Text(String((profile?.displayName ?? user?.name ?? "G").prefix(1)))
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(.black)
                )
                .shadow(color: TCTheme.gold.opacity(0.35), radius: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(profile?.displayName ?? user?.name ?? "Golfer")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                HStack(spacing: 8) {
                    TCPill(text: profile?.handedness.rawValue ?? "Right", color: TCTheme.cyan)
                    TCPill(text: user?.subscriptionStatus.rawValue.capitalized ?? "Free", color: TCTheme.gold)
                }
                Text(profile?.homeCourseName.isEmpty == false ? profile!.homeCourseName : "Home course not set")
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
            }
            Spacer()
        }
        .tcCard()
    }

    // MARK: Stats Row

    private var statsRow: some View {
        HStack(spacing: 10) {
            TCMetricTile(label: "SHOTS", value: "142", unit: "", accent: TCTheme.gold)
            TCMetricTile(label: "SESSIONS", value: "8", unit: "", accent: TCTheme.sage)
            TCMetricTile(label: "ROUNDS", value: "3", unit: "", accent: TCTheme.cyan)
        }
    }

    // MARK: Saved Shots

    private var savedShotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TCSectionHeader(
                title: "Saved Shots",
                trailing: AnyView(
                    Button("View All") { showSessions = true }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TCTheme.gold)
                )
            )
            VStack(spacing: 10) {
                savedShotRow(club: "Driver", carry: 241, speed: 148, ago: "2h ago")
                savedShotRow(club: "7 Iron", carry: 162, speed: 112, ago: "2h ago")
                savedShotRow(club: "PW",     carry: 108, speed: 94,  ago: "Yesterday")
            }
        }
    }

    private func savedShotRow(club: String, carry: Int, speed: Int, ago: String) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(TCTheme.cyan.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "smallcircle.filled.circle")
                    .font(.system(size: 15))
                    .foregroundColor(TCTheme.cyan))
            VStack(alignment: .leading, spacing: 3) {
                Text(club).font(.system(size: 14, weight: .semibold)).foregroundColor(TCTheme.textPrimary)
                Text(ago).font(.system(size: 12)).foregroundColor(TCTheme.textMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(carry) yd").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(TCTheme.cyan)
                Text("\(speed) mph").font(.system(size: 11)).foregroundColor(TCTheme.textMuted)
            }
        }
        .tcCard()
    }

    // MARK: Gear / Clubs

    private var gearSection: some View {
        VStack(spacing: 0) {
            TCSectionHeader(title: "Clubs in Bag").padding(.bottom, 10)
            Button { showClubs = true } label: {
                TCSettingsRow(icon: "figure.golf", title: "Manage Clubs", value: "View bag", accent: TCTheme.sage)
            }
            .buttonStyle(.plain)
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .strokeBorder(TCTheme.border, lineWidth: 1)
            )
        }
    }

    // MARK: Settings

    private var settingsSection: some View {
        VStack(spacing: 0) {
            TCSectionHeader(title: "Settings").padding(.bottom, 10)
            VStack(spacing: 0) {
                TCSettingsRow(icon: "hand.raised.fill", title: "Handedness",
                             value: profile?.handedness.rawValue ?? "Right", accent: TCTheme.cyan)
                TCDivider()
                TCSettingsRow(icon: "ruler.fill", title: "Distance Units",
                             value: profile?.distanceUnit.rawValue ?? "Yards", accent: TCTheme.textMuted)
                TCDivider()
                TCSettingsRow(icon: "camera.fill", title: "Frame Rate", value: "240 fps", accent: TCTheme.gold)
                TCDivider()
                TCSettingsRow(icon: "info.circle.fill", title: "Version", value: "1.0.0",
                             accent: TCTheme.textMuted, showChevron: false)
            }
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .strokeBorder(TCTheme.border, lineWidth: 1)
            )
        }
    }

    // MARK: Sign Out

    private var signOutButton: some View {
        Button { Task { await session.signOut() } } label: {
            Text("Sign Out")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(TCTheme.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(TCTheme.danger.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(TCTheme.danger.opacity(0.30), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
