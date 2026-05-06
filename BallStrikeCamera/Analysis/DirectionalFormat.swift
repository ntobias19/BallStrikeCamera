import Foundation

struct DirectionalFormat {
    static func angleLR(_ degrees: Double, positiveLabel: String = "R", negativeLabel: String = "L") -> String {
        let label = degrees >= 0 ? positiveLabel : negativeLabel
        return String(format: "%.1f° %@", abs(degrees), label)
    }

    static func spinLR(_ rpm: Double) -> String {
        let label = rpm >= 0 ? "R" : "L"
        return String(format: "%.0f rpm %@", abs(rpm), label)
    }
}
