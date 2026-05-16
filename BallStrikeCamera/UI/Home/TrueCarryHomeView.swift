import SwiftUI

struct TrueCarryHomeView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var showCamera = false
    var selectTab: (TCTab) -> Void

    private var firstName: String {
        let name = session.userProfile?.displayName ?? session.currentUser?.name ?? "Golfer"
        return name.components(separatedBy: " ").first ?? name
    }

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerBar
                    VStack(spacing: TCTheme.sectionGap) {
                        greetingCard
                        heroStartCard
                        activitySection
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 12)
                }
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showCamera) {
            RangeCameraScreen().ignoresSafeArea().statusBarHidden(true)
        }
    }

    // MARK: Header

    private var headerBar: some View {
        HStack {
            TrueCarryLogo(size: 26)
            Spacer()
            Button {} label: {
                Circle()
                    .fill(TCTheme.panel)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Text(String((session.userProfile?.displayName ?? session.currentUser?.name ?? "G").prefix(1)))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(TCTheme.gold)
                    )
                    .overlay(Circle().strokeBorder(TCTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: Greeting

    private var greetingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Good to see you,")
                        .font(.system(size: 14))
                        .foregroundColor(TCTheme.textMuted)
                    Text(firstName)
                        .font(.system(size: 30, weight: .black))
                        .foregroundColor(TCTheme.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Handicap")
                        .font(.system(size: 10))
                        .foregroundColor(TCTheme.textMuted)
                    Text("—")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(TCTheme.gold)
                }
            }
            HStack(spacing: 8) {
                TCPill(text: "Range Ready", color: TCTheme.sage)
                TCPill(text: "240 FPS", color: TCTheme.cyan)
            }
        }
        .tcCard()
    }

    // MARK: Hero Start Card

    private var heroStartCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sage accent line
            LinearGradient(colors: [TCTheme.sage, TCTheme.gold], startPoint: .leading, endPoint: .trailing)
                .frame(height: 3)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: TCTheme.cardRadius, bottomLeadingRadius: 0,
                                                   bottomTrailingRadius: 0, topTrailingRadius: TCTheme.cardRadius))

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start a Session")
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(TCTheme.textPrimary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Track every shot.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(TCTheme.textSecondary)
                        Text("Know every yard.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(TCTheme.textSecondary)
                        Text("Play your best.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(TCTheme.gold)
                    }
                }

                HStack(spacing: 10) {
                    TCPrimaryGoldButton(title: "Open Camera", icon: "camera.fill") {
                        showCamera = true
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        selectTab(.play)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("Choose Mode")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(TCTheme.sage)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(TCTheme.sage.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(TCTheme.sage.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .background(TCTheme.panel)
        }
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                .strokeBorder(TCTheme.border, lineWidth: 1)
        )
        .shadow(color: TCTheme.sage.opacity(0.12), radius: 18, x: 0, y: 6)
    }

    // MARK: Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            TCSectionHeader(
                title: "Recent Activity",
                trailing: AnyView(
                    Button("See All") {}
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TCTheme.gold)
                )
            )

            VStack(spacing: 10) {
                TCSessionCard(
                    icon: "target",
                    mode: "Range Session",
                    detail: "7 Iron · 22 shots · 2h ago",
                    stat: "162",
                    statLabel: "avg carry yd",
                    accent: TCTheme.cyan
                )
                TCSessionCard(
                    icon: "flag.fill",
                    mode: "Course Round",
                    detail: "Pebble Beach · Front 9 · Yesterday",
                    stat: "+3",
                    statLabel: "score",
                    accent: TCTheme.sage
                )
                TCSessionCard(
                    icon: "display",
                    mode: "Sim Session",
                    detail: "GSPro · 14 shots · 3h ago",
                    stat: "241",
                    statLabel: "avg carry yd",
                    accent: TCTheme.gold
                )
            }
        }
    }
}
