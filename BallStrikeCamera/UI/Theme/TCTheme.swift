import SwiftUI

// MARK: - True Carry Design System

enum TCTheme {
    // MARK: Backgrounds
    static let background     = Color(red: 0.008, green: 0.043, blue: 0.075)  // #020B13
    static let backgroundMid  = Color(red: 0.016, green: 0.078, blue: 0.133)  // #041420
    static let backgroundBot  = Color(red: 0.024, green: 0.102, blue: 0.165)  // #061A2A
    static let panel          = Color(red: 0.024, green: 0.090, blue: 0.145)  // #061725
    static let panelRaised    = Color(red: 0.039, green: 0.129, blue: 0.200)  // #0A2133
    static let panelDeep      = Color(red: 0.016, green: 0.063, blue: 0.110)  // #04101C
    static let glassPanel     = Color(red: 0.028, green: 0.106, blue: 0.169).opacity(0.88)

    // MARK: Text
    static let textPrimary    = Color(red: 0.969, green: 0.953, blue: 0.918)  // #F7F3EA
    static let textSecondary  = Color(red: 0.765, green: 0.796, blue: 0.816)  // #C3CBD0
    static let textMuted      = Color(red: 0.455, green: 0.506, blue: 0.541)  // #748289
    static let textUltraMuted = Color(red: 0.310, green: 0.357, blue: 0.388)  // #4F5B63

    // MARK: Accents
    static let gold           = Color(red: 0.851, green: 0.643, blue: 0.255)  // #D9A441
    static let goldLight      = Color(red: 0.886, green: 0.718, blue: 0.337)  // #E2B756
    static let goldDim        = Color(red: 0.620, green: 0.459, blue: 0.165)  // #9E752A
    static let sage           = Color(red: 0.553, green: 0.729, blue: 0.369)  // #8DBA5E
    static let sageBright     = Color(red: 0.655, green: 0.812, blue: 0.227)  // #A7CF3A
    static let sageDeep       = Color(red: 0.494, green: 0.627, blue: 0.302)  // #7EA04D
    static let deepGreen      = Color(red: 0.129, green: 0.247, blue: 0.184)  // #213F2F
    static let fairway        = Color(red: 0.176, green: 0.380, blue: 0.220)  // #2D6138
    static let cyan           = Color(red: 0.00,  green: 0.851, blue: 1.000)  // #00D9FF
    static let danger         = Color(red: 0.847, green: 0.361, blue: 0.361)  // #D85C5C

    // MARK: Borders
    static let border         = Color.white.opacity(0.12)
    static let borderMedium   = Color.white.opacity(0.18)
    static let borderGold     = gold.opacity(0.35)
    static let borderSage     = sage.opacity(0.30)

    // MARK: Spacing
    static let hPad: CGFloat        = 20
    static let cardRadius: CGFloat  = 22
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
        colors: [Color(red: 0.04, green: 0.12, blue: 0.08), Color(red: 0.01, green: 0.05, blue: 0.03)],
        startPoint: .top, endPoint: .bottom
    )
    static let dockBackground = Color(red: 0.016, green: 0.067, blue: 0.118).opacity(0.97)
    static let courseGradient = LinearGradient(
        colors: [sageDeep, deepGreen],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: Shadows
    static let goldShadow = Color(red: 0.851, green: 0.643, blue: 0.255).opacity(0.30)
    static let sageShadow = Color(red: 0.553, green: 0.729, blue: 0.369).opacity(0.25)
    static let panelShadow = Color.black.opacity(0.40)
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
            .background(.ultraThinMaterial.opacity(0.3))
            .background(TCTheme.panel.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .strokeBorder(TCTheme.borderMedium, lineWidth: 1)
            )
    }

    func tcGoldGlow(radius: CGFloat = 18) -> some View {
        self.shadow(color: TCTheme.goldShadow, radius: radius, x: 0, y: 0)
    }

    func tcSageGlow(radius: CGFloat = 14) -> some View {
        self.shadow(color: TCTheme.sageShadow, radius: radius, x: 0, y: 0)
    }

    func tcPanelShadow() -> some View {
        self.shadow(color: TCTheme.panelShadow, radius: 12, x: 0, y: 4)
    }
}
