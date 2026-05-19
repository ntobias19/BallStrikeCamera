import SwiftUI

/// OpenStreetMap attribution required by the ODbL license. Subtle but always-visible.
/// Tapping opens the OSM copyright page in Safari.
struct OSMAttributionBadge: View {

    private let copyrightURL = URL(string: "https://www.openstreetmap.org/copyright")!

    var body: some View {
        Link(destination: copyrightURL) {
            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.70))
                Text("© OpenStreetMap")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.80))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.55))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
