import SwiftUI

// MARK: - True Carry Design System

enum TCTheme {
    // MARK: Backgrounds
    static let background     = Color(red: 0.025, green: 0.028, blue: 0.026)
    static let backgroundMid  = background
    static let backgroundBot  = background
    static let panel          = Color.white.opacity(0.045)
    static let panelRaised    = Color.white.opacity(0.070)
    static let panelDeep      = Color.black.opacity(0.30)
    static let glassPanel     = panel

    // MARK: Text
    static let textPrimary    = Color.white
    static let textSecondary  = Color.white.opacity(0.78)
    static let textMuted      = Color.white.opacity(0.54)
    static let textUltraMuted = Color.white.opacity(0.34)

    // MARK: Accents
    static let gold           = Color(red: 0.73, green: 0.96, blue: 0.24)
    static let goldLight      = Color(red: 0.86, green: 1.00, blue: 0.42)
    static let goldDim        = Color(red: 0.58, green: 0.78, blue: 0.18)
    static let sage           = Color(red: 0.47, green: 0.76, blue: 0.42)
    static let sageBright     = Color(red: 0.64, green: 0.90, blue: 0.52)
    static let sageDeep       = Color(red: 0.20, green: 0.36, blue: 0.24)
    static let deepGreen      = Color(red: 0.08, green: 0.13, blue: 0.09)
    static let fairway        = Color(red: 0.30, green: 0.62, blue: 0.34).opacity(0.58)
    static let cyan           = Color.white.opacity(0.82)
    static let danger         = Color(red: 0.93, green: 0.47, blue: 0.47)

    // MARK: Borders
    static let border         = Color.white.opacity(0.11)
    static let borderMedium   = Color.white.opacity(0.16)
    static let borderGold     = gold.opacity(0.24)
    static let borderSage     = sage.opacity(0.22)

    // MARK: Spacing
    static let hPad: CGFloat        = 20
    static let cardRadius: CGFloat  = 18
    static let sectionGap: CGFloat  = 22
    static let rowRadius: CGFloat   = 14

    // MARK: Gradients
    static let goldGradient = LinearGradient(
        colors: [goldLight, gold],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let sageGradient = LinearGradient(
        colors: [sageBright, sageDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let backgroundGradient = LinearGradient(
        colors: [background, backgroundMid, backgroundBot],
        startPoint: .top, endPoint: .bottom
    )
    static let heroGradient = LinearGradient(
        colors: [panelRaised, panel],
        startPoint: .top, endPoint: .bottom
    )
    static let dockBackground = Color(red: 0.015, green: 0.017, blue: 0.016).opacity(0.96)
    static let courseGradient = LinearGradient(
        colors: [panelRaised, panel],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: Shadows
    static let goldShadow = Color.clear
    static let sageShadow = Color.clear
    static let panelShadow = Color.clear
}

// MARK: - ViewModifier extensions

extension View {
    /// Standard dark panel card
    func tcCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .strokeBorder(TCTheme.border, lineWidth: 1)
            )
    }

    /// Glass-effect dark card
    func tcGlassCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .strokeBorder(TCTheme.border, lineWidth: 1)
            )
    }

    func tcGoldGlow(radius: CGFloat = 18) -> some View {
        self.shadow(color: TCTheme.goldShadow, radius: radius, x: 0, y: 0)
    }

    func tcSageGlow(radius: CGFloat = 14) -> some View {
        self.shadow(color: TCTheme.sageShadow, radius: radius, x: 0, y: 0)
    }

    func tcPanelShadow() -> some View {
        self
    }
}
