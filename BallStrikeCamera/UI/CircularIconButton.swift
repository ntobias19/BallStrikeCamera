import SwiftUI

struct CircularIconButton: View {
    let icon: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(isActive ? .white : LaunchMonitorTheme.textPrimary)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isActive
                                    ? [LaunchMonitorTheme.accentSky, LaunchMonitorTheme.accentFairway]
                                    : [LaunchMonitorTheme.panelRaisedTop, LaunchMonitorTheme.panelRaisedBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Circle()
                        .stroke(isActive ? Color.white.opacity(0.28) : LaunchMonitorTheme.outlineStrong, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(isActive ? 0.28 : 0.18), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon)
    }
}
