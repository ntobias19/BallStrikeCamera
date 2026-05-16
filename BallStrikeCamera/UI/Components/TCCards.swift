import SwiftUI

// MARK: - TC Section Header

struct TCSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(TCTheme.textMuted)
                    .tracking(1.4)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 13))
                        .foregroundColor(TCTheme.textSecondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

// MARK: - TC Gold Primary Button

struct TCPrimaryGoldButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .bold)) }
                Text(title).font(.system(size: 16, weight: .bold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(TCTheme.goldGradient)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .tcGoldGlow()
    }
}

// MARK: - TC Secondary Pill Button

struct TCSecondaryButton: View {
    let title: String
    var icon: String? = nil
    var color: Color = TCTheme.gold
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TC Metric Tile

struct TCMetricTile: View {
    let label: String
    let value: String
    var unit: String = ""
    var accent: Color = TCTheme.gold

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textMuted)
                }
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .tcCard(padding: 0)
        .padding(0)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(TCTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - TC Settings Row

struct TCSettingsRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    var accent: Color = TCTheme.gold
    var showChevron: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(accent)
            }
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(TCTheme.textPrimary)
            Spacer()
            if let val = value {
                Text(val)
                    .font(.system(size: 13))
                    .foregroundColor(TCTheme.textMuted)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - TC Session Card

struct TCSessionCard: View {
    let icon: String
    let mode: String
    let detail: String
    let stat: String
    let statLabel: String
    let accent: Color
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(stat)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(accent)
                    Text(statLabel)
                        .font(.system(size: 10))
                        .foregroundColor(TCTheme.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .tcCard()
    }
}

// MARK: - TC Status Pill

struct TCPill: View {
    let text: String
    var color: Color = TCTheme.gold

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - TC Mode Card

struct TCModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TCTheme.textMuted.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .tcCard()
    }
}

// MARK: - TC Divider

struct TCDivider: View {
    var body: some View {
        Rectangle()
            .fill(TCTheme.border)
            .frame(height: 1)
            .padding(.horizontal, 14)
    }
}
