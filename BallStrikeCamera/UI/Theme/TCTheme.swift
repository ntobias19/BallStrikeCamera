import SwiftUI

// MARK: - True Carry Design System

enum TCTheme {
    // MARK: Backgrounds
    static let background    = Color(red: 0.012, green: 0.067, blue: 0.118)  // #031122
    static let panel         = Color(red: 0.028, green: 0.106, blue: 0.169)  // #071B2B
    static let panelRaised   = Color(red: 0.039, green: 0.129, blue: 0.200)  // #0A2133
    static let panelDeep     = Color(red: 0.016, green: 0.078, blue: 0.133)  // #041420

    // MARK: Text
    static let textPrimary   = Color(red: 0.969, green: 0.953, blue: 0.918)  // #F7F3EA
    static let textSecondary = Color(red: 0.765, green: 0.796, blue: 0.816)  // #C3CBD0
    static let textMuted     = Color(red: 0.455, green: 0.506, blue: 0.541)  // #748289

    // MARK: Accents
    static let gold          = Color(red: 0.851, green: 0.643, blue: 0.255)  // #D9A441
    static let goldLight     = Color(red: 0.886, green: 0.718, blue: 0.337)  // #E2B756
    static let sage          = Color(red: 0.553, green: 0.729, blue: 0.369)  // #8DBA5E
    static let sageDeep      = Color(red: 0.494, green: 0.627, blue: 0.302)  // #7EA04D
    static let deepGreen     = Color(red: 0.129, green: 0.247, blue: 0.184)  // #213F2F
    static let fairway       = Color(red: 0.176, green: 0.380, blue: 0.220)  // #2D6138
    static let cyan          = Color(red: 0.00,  green: 0.851, blue: 1.000)  // #00D9FF
    static let danger        = Color(red: 0.847, green: 0.361, blue: 0.361)  // #D85C5C

    // MARK: Borders
    static let border        = Color.white.opacity(0.10)
    static let borderMedium  = Color.white.opacity(0.16)

    // MARK: Spacing
    static let hPad: CGFloat    = 20
    static let cardRadius: CGFloat = 18
    static let sectionGap: CGFloat = 24

    // MARK: Gradients
    static let goldGradient = LinearGradient(
        colors: [goldLight, gold],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let sageGradient = LinearGradient(
        colors: [sage, sageDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let darkGradient = LinearGradient(
        colors: [background, panelDeep],
        startPoint: .top, endPoint: .bottom
    )
    static let courseGradient = LinearGradient(
        colors: [sageDeep, deepGreen],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let dockBackground = Color(red: 0.024, green: 0.086, blue: 0.145).opacity(0.96)

    // MARK: Card helpers
    static func panelFill(opacity: Double = 1.0) -> some ShapeStyle { panel.opacity(opacity) }
}

// MARK: - ViewModifier extensions

extension View {
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

    func tcGlassCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(.ultraThinMaterial.opacity(0.7))
            .background(TCTheme.panel.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .strokeBorder(TCTheme.borderMedium, lineWidth: 1)
            )
    }

    func tcGoldGlow(radius: CGFloat = 18) -> some View {
        self.shadow(color: TCTheme.gold.opacity(0.28), radius: radius, x: 0, y: 0)
    }

    func tcSageGlow(radius: CGFloat = 14) -> some View {
        self.shadow(color: TCTheme.sage.opacity(0.30), radius: radius, x: 0, y: 0)
    }
}
