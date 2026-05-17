import SwiftUI

// MARK: - Tab Enum

enum TCTab: Int, CaseIterable {
    case home = 0, insights = 1, play = 2, locker = 3, courses = 4

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

// MARK: - Scalloped Dock Shape

private struct ScallopedDockShape: Shape {
    var cutRadius: CGFloat = 34
    var cornerR: CGFloat   = 24

    func path(in rect: CGRect) -> Path {
        let midX = rect.midX
        let top  = rect.minY
        let cr   = cornerR
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + cr, y: top))
        p.addLine(to: CGPoint(x: midX - cutRadius - 5, y: top))
        p.addArc(center: CGPoint(x: midX, y: top),
                 radius: cutRadius + 5,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: rect.maxX - cr, y: top))
        p.addArc(center: CGPoint(x: rect.maxX - cr, y: top + cr),
                 radius: cr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cr))
        p.addArc(center: CGPoint(x: rect.maxX - cr, y: rect.maxY - cr),
                 radius: cr, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + cr, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + cr, y: rect.maxY - cr),
                 radius: cr, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: top + cr))
        p.addArc(center: CGPoint(x: rect.minX + cr, y: top + cr),
                 radius: cr, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Bottom Dock

struct TCBottomDock: View {
    @Binding var selectedTab: TCTab
    @Environment(\.safeAreaInsets) private var safeInsets

    private let cutRadius:  CGFloat = 36
    private let dockHeight: CGFloat = 52   // premium slim dock

    var body: some View {
        ZStack(alignment: .top) {
            // Dock backdrop (glass + dark layer)
            ScallopedDockShape(cutRadius: cutRadius)
                .fill(.ultraThinMaterial.opacity(0.20))
                .frame(height: dockHeight + safeInsets.bottom + 4)

            ScallopedDockShape(cutRadius: cutRadius)
                .fill(Color(red:0.010,green:0.040,blue:0.078).opacity(0.95))
                .frame(height: dockHeight + safeInsets.bottom + 4)
                .overlay(
                    ScallopedDockShape(cutRadius: cutRadius)
                        .stroke(TCTheme.gold.opacity(0.32), lineWidth: 1.0)
                        .frame(height: dockHeight + safeInsets.bottom + 4)
                )
                .shadow(color: Color.black.opacity(0.55), radius: 18, x: 0, y: -4)

            // Top highlight line (premium edge)
            ScallopedDockShape(cutRadius: cutRadius)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                .frame(height: dockHeight + safeInsets.bottom + 4)

            // Tab items
            HStack(alignment: .bottom, spacing: 0) {
                ForEach([TCTab.home, .insights], id: \.rawValue) { dockItem($0) }
                Spacer().frame(width: (cutRadius + 5) * 2 + 6)
                ForEach([TCTab.locker, .courses], id: \.rawValue) { dockItem($0) }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, safeInsets.bottom + 4)

            // Elevated center Play button
            centerButton
                .offset(y: -(cutRadius - 14))
        }
        .padding(.horizontal, 12)
    }

    private func dockItem(_ tab: TCTab) -> some View {
        let selected = selectedTab == tab
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { selectedTab = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 19, weight: selected ? .bold : .regular))
                    .foregroundColor(selected ? TCTheme.gold : TCTheme.textSecondary.opacity(0.75))
                Text(tab.label)
                    .font(.system(size: 9.5, weight: selected ? .bold : .medium))
                    .foregroundColor(selected ? TCTheme.gold : TCTheme.textSecondary.opacity(0.75))
                // Underline bar
                Rectangle()
                    .fill(selected ? TCTheme.gold : Color.clear)
                    .frame(width: selected ? 20 : 0, height: 1.5)
                    .clipShape(Capsule())
                    .animation(.easeInOut(duration: 0.20), value: selected)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    private var centerButton: some View {
        let selected = selectedTab == .play
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { selectedTab = .play }
        } label: {
            ZStack {
                // Diffuse outer glow
                Circle()
                    .fill(selected ? TCTheme.gold.opacity(0.38) : TCTheme.sage.opacity(0.22))
                    .frame(width: cutRadius * 2 + 24, height: cutRadius * 2 + 24)
                    .blur(radius: 14)
                // Gold trim ring
                Circle()
                    .strokeBorder(TCTheme.goldGradient, lineWidth: selected ? 2.5 : 1.5)
                    .frame(width: cutRadius * 2 + 4, height: cutRadius * 2 + 4)
                // Button face
                Circle()
                    .fill(selected
                          ? TCTheme.goldGradient
                          : LinearGradient(
                                colors: [TCTheme.panelRaised, TCTheme.panel],
                                startPoint: .top, endPoint: .bottom))
                    .frame(width: cutRadius * 2, height: cutRadius * 2)
                // Icon
                Image(systemName: "flag.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(selected ? Color.black : TCTheme.sage)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Safe Area Insets (environment key)

private struct SafeAreaInsetsKey: EnvironmentKey {
    static var defaultValue: EdgeInsets = .init()
}

extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        get { self[SafeAreaInsetsKey.self] }
        set { self[SafeAreaInsetsKey.self] = newValue }
    }
}

// MARK: - App Shell

struct TrueCarryAppShell: View {
    @State private var selectedTab: TCTab = .home
    @EnvironmentObject var session: AuthSessionStore
    @EnvironmentObject var camera: CameraController

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                tabContent
                    .ignoresSafeArea(edges: .bottom)
                    .environment(\.safeAreaInsets, geo.safeAreaInsets)

                VStack(spacing: 0) {
                    Spacer()
                    TCBottomDock(selectedTab: $selectedTab)
                        .environment(\.safeAreaInsets, geo.safeAreaInsets)
                }
                .ignoresSafeArea(.keyboard)
            }
        }
        .background(TCTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
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
