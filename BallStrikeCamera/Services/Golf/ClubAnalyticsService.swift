import Foundation
import CoreLocation

// MARK: - Output models

struct ClubAnalytics {
    let category: ShotClub.ClubCategory
    let sampleCount: Int
    let avgCarryYds: Double
    let avgTotalYds: Double
    /// One-sigma lateral dispersion in yards (left/right of intended line).
    let lateralStdDevYds: Double
    /// One-sigma longitudinal dispersion in yards (short/long of average).
    let longitudinalStdDevYds: Double
    /// Miss tendency: signed yards (negative = left, positive = right).
    let missBiasYds: Double
    /// Confidence in [0, 1] based on sample size and outlier ratio.
    let confidence: Double
}

// MARK: - Service

/// Aggregates `TrackedShot` data into per-club analytics suitable for the bag stats screen
/// and the upcoming AI caddie. Pure functions; no I/O.
enum ClubAnalyticsService {

    /// Lower bound on samples needed before a club is considered statistically meaningful.
    private static let minSamples = 4

    /// Outlier rejection threshold in standard deviations.
    private static let outlierZScore = 2.5

    /// Compute per-club analytics from a flat list of tracked shots.
    /// Filters:
    /// - Penalties and mishits excluded.
    /// - Clubs with fewer than `minSamples` shots return `nil` for that category.
    /// - Outliers ≥ `outlierZScore` σ from the mean are dropped on a second pass.
    static func aggregate(_ shots: [TrackedShot]) -> [ShotClub.ClubCategory: ClubAnalytics] {
        var byCategory: [ShotClub.ClubCategory: [TrackedShot]] = [:]
        for s in shots where s.result.isMeaningfulForCarry && s.club != nil {
            byCategory[s.club!.category, default: []].append(s)
        }
        var out: [ShotClub.ClubCategory: ClubAnalytics] = [:]
        for (cat, group) in byCategory where group.count >= minSamples {
            if let analytics = analytics(for: cat, shots: group) {
                out[cat] = analytics
            }
        }
        return out
    }

    private static func analytics(for cat: ShotClub.ClubCategory,
                                   shots: [TrackedShot]) -> ClubAnalytics? {
        // First pass: mean carry; reject outliers on a second pass.
        let firstDistances = shots.map { $0.distanceYards }
        let firstMean = firstDistances.reduce(0, +) / Double(firstDistances.count)
        let firstStd  = stdDev(firstDistances, mean: firstMean)
        let kept = shots.filter { abs($0.distanceYards - firstMean) <= outlierZScore * max(firstStd, 1) }
        guard kept.count >= minSamples else { return nil }

        let carryVals = kept.compactMap { $0.carryYards ?? $0.distanceYards }
        let totalVals = kept.map { $0.distanceYards }
        let avgCarry  = carryVals.reduce(0, +) / Double(carryVals.count)
        let avgTotal  = totalVals.reduce(0, +) / Double(totalVals.count)

        // Lateral dispersion: project end coord onto a per-shot tee→hole-center axis.
        // Approximation: assume the shot vector itself is the "intended" axis for now.
        // (Replaces with intended-line vector once aim direction is stored.)
        let lateralDevs    = kept.map { lateralDeviation(of: $0) }
        let lateralMean    = lateralDevs.reduce(0, +) / Double(lateralDevs.count)
        let lateralStd     = stdDev(lateralDevs, mean: lateralMean)
        let longitudinalStd = stdDev(totalVals, mean: avgTotal)

        // Confidence: scales with sample size and the inverse of outlier ratio.
        let droppedRatio = 1.0 - Double(kept.count) / Double(shots.count)
        let sampleFactor = min(1.0, Double(kept.count) / 30.0)
        let confidence   = max(0.0, min(1.0, sampleFactor * (1 - droppedRatio)))

        return ClubAnalytics(
            category: cat,
            sampleCount:           kept.count,
            avgCarryYds:           avgCarry,
            avgTotalYds:           avgTotal,
            lateralStdDevYds:      lateralStd,
            longitudinalStdDevYds: longitudinalStd,
            missBiasYds:           lateralMean,
            confidence:            confidence
        )
    }

    // MARK: - Math helpers

    private static func stdDev(_ xs: [Double], mean: Double) -> Double {
        guard xs.count > 1 else { return 0 }
        let sq = xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
        return sqrt(sq / Double(xs.count - 1))
    }

    /// Signed lateral deviation in yards. Sign convention: positive = right of start→end axis.
    /// MVP: zero, since we don't store an intended line yet — kept as a stub so callers can
    /// compute miss bias once aim is captured.
    private static func lateralDeviation(of shot: TrackedShot) -> Double {
        // Placeholder for future intended-line analysis.
        0
    }
}
