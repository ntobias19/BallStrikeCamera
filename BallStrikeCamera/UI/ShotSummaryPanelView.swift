import SwiftUI

struct ShotSummaryPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Total")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.green.opacity(0.8))

                Spacer()

                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("247")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundColor(Color.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text("yd")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer(minLength: 8)

            HStack(spacing: 0) {
                summaryMetric(label: "Carry", value: "232", unit: "yd")
                    .frame(maxWidth: .infinity, alignment: .leading)

                summaryMetric(label: "Height", value: "86", unit: "ft")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryMetric(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))

                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(unit)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }
}
