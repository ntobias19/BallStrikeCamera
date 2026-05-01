import SwiftUI

struct CompactMetricsBarView: View {
    private let metrics = [
        Metric(label: "Launch Angle", value: "13.2", unit: "°"),
        Metric(label: "Launch Direction", value: "R1.4", unit: "°"),
        Metric(label: "Ball Speed", value: "153", unit: "mph"),
        Metric(label: "Club Speed", value: "104", unit: "mph"),
        Metric(label: "Smash Factor", value: "1.47", unit: "")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                compactMetric(metric)

                if index < metrics.count - 1 {
                    divider
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func compactMetric(_ metric: Metric) -> some View {
        VStack(spacing: 4) {
            Text(metric.label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(metric.value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                if !metric.unit.isEmpty {
                    Text(metric.unit)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 30)
    }
}

private struct Metric: Identifiable {
    let label: String
    let value: String
    let unit: String

    var id: String { label }
}
