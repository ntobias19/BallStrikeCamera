import SwiftUI

// MARK: - True Carry Custom Bottom Dock

enum TCTab: Int, CaseIterable {
    case home     = 0
    case insights = 1
    case play     = 2
    case locker   = 3
    case courses  = 4

    var label: String {
        switch self {
        case .home:     return "Home"
        case .insights: return "Insights"
        case .play:     return "Play"
        case .locker:   return "Locker"
        case .courses:  return "Courses"
        }
    }

    var icon: String {
        switch self {
        case .home:     return "house.fill"
        case .insights: return "chart.bar.xaxis"
        case .play:     return "flag.fill"
        case .locker:   return "folder.fill"
        case .courses:  return "map.fill"
        }
    }

    var isCenter: Bool { self == .play }
}

struct TCBottomDock: View {
    @Binding var selectedTab: TCTab

    // Safe area bottom inset
    @Environment(\.safeAreaInsets) private var safeInsets

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // Left 2 tabs
            ForEach([TCTab.home, .insights], id: \.rawValue) { tab in
                dockItem(tab)
            }

            // Center Play button
            centerButton

            // Right 2 tabs
            ForEach([TCTab.locker, .courses], id: \.rawValue) { tab in
                dockItem(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, safeInsets.bottom + 4)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(TCTheme.dockBackground)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.7)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(TCTheme.borderMedium, lineWidth: 1)
                )
        }
        .padding(.horizontal, 16)
    }

    private func dockItem(_ tab: TCTab) -> some View {
        let selected = selectedTab == tab
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: selected ? .bold : .regular))
                    .foregroundColor(selected ? TCTheme.gold : TCTheme.textMuted)
                    .scaleEffect(selected ? 1.05 : 1.0)

                Text(tab.label)
                    .font(.system(size: 10, weight: selected ? .bold : .medium))
                    .foregroundColor(selected ? TCTheme.gold : TCTheme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var centerButton: some View {
        let selected = selectedTab == .play
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = .play
            }
        } label: {
            ZStack {
                Circle()
                    .fill(selected ? TCTheme.goldGradient : LinearGradient(colors: [TCTheme.panelRaised, TCTheme.panel], startPoint: .top, endPoint: .bottom))
                    .frame(width: 58, height: 58)
                    .shadow(color: selected ? TCTheme.gold.opacity(0.40) : .clear, radius: 14, x: 0, y: 0)
                    .overlay(
                        Circle()
                            .strokeBorder(selected ? Color.clear : TCTheme.borderMedium, lineWidth: 1.5)
                    )
                Image(systemName: "flag.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(selected ? .black : TCTheme.textMuted)
            }
            .offset(y: -10)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Safe Area Insets Environment Key

private struct SafeAreaInsetsKey: EnvironmentKey {
    static var defaultValue: EdgeInsets = .init()
}

extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        get { self[SafeAreaInsetsKey.self] }
        set { self[SafeAreaInsetsKey.self] = newValue }
    }
}

// MARK: - True Carry App Shell

struct TrueCarryAppShell: View {
    @State private var selectedTab: TCTab = .home
    @EnvironmentObject var session: AuthSessionStore
    @EnvironmentObject var camera: CameraController

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            tabContent
                .ignoresSafeArea(edges: .bottom)

            // Floating dock
            VStack(spacing: 0) {
                Spacer()
                TCBottomDock(selectedTab: $selectedTab)
            }
            .ignoresSafeArea(.keyboard)
        }
        .background(TCTheme.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            NavigationStack { TrueCarryHomeView(selectTab: { selectedTab = $0 }) }
        case .insights:
            NavigationStack { TrueCarryInsightsView() }
        case .play:
            NavigationStack { TrueCarryPlayView() }
        case .locker:
            NavigationStack { TrueCarryLockerView() }
        case .courses:
            NavigationStack { TrueCarryCoursesView() }
        }
    }
}
