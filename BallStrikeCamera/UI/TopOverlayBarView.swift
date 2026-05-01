import SwiftUI

struct TopOverlayBarView: View {
    let title: String
    var subtitle: String?
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CircularIconButton(icon: "chevron.left", action: onBack)
                .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
    }
}
