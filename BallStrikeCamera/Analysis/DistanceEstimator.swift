import Foundation

struct DistanceEstimate {
    let carryYards: Double?
    let totalYards: Double?
    let method: String
    let warnings: [String]
}

struct DistanceEstimator {
    func estimate(ballSpeedMph: Double?, vlaDegrees: Double?, hlaDegrees: Double?) -> DistanceEstimate {
        var warnings = [
            "Carry/total are rough estimates because spin, ball height calibration, wind, and ground interaction are unknown."
        ]

        guard let ballSpeedMph, ballSpeedMph > 0 else {
            warnings.append("Distance estimate skipped: missing ball speed.")
            return DistanceEstimate(carryYards: nil, totalYards: nil, method: "unavailable", warnings: warnings)
        }

        guard let vlaDegrees, vlaDegrees.isFinite else {
            warnings.append("Distance estimate skipped: missing vertical launch angle.")
            return DistanceEstimate(carryYards: nil, totalYards: nil, method: "unavailable", warnings: warnings)
        }

        let clampedLaunch = min(max(vlaDegrees, 1), 45)
        if clampedLaunch != vlaDegrees {
            warnings.append(String(format: "VLA %.1f was clamped to %.1f degrees for the rough distance model.", vlaDegrees, clampedLaunch))
        }
        if hlaDegrees == nil {
            warnings.append("Horizontal launch angle unavailable; distance model ignores lateral curve.")
        }

        let speedMetersPerSecond = ballSpeedMph / 2.23694
        let theta = clampedLaunch * .pi / 180
        let gravity = 9.80665
        let idealRangeMeters = speedMetersPerSecond * speedMetersPerSecond * sin(2 * theta) / gravity

        let dragFactor: Double
        if clampedLaunch < 8 {
            dragFactor = 0.45
        } else if clampedLaunch < 18 {
            dragFactor = 0.56
        } else if clampedLaunch < 30 {
            dragFactor = 0.62
        } else {
            dragFactor = 0.52
        }

        let carryYards = clamp(idealRangeMeters * dragFactor * 1.09361, min: 0, max: 400)

        let rolloutFactor: Double
        if clampedLaunch < 8 {
            rolloutFactor = 0.45
        } else if clampedLaunch < 15 {
            rolloutFactor = 0.25
        } else if clampedLaunch < 25 {
            rolloutFactor = 0.12
        } else {
            rolloutFactor = 0.08
        }

        let totalYards = clamp(carryYards * (1 + rolloutFactor), min: carryYards, max: 450)

        return DistanceEstimate(
            carryYards: carryYards,
            totalYards: totalYards,
            method: String(format: "ideal_projectile_drag_factor_%.2f_rollout_%.2f", dragFactor, rolloutFactor),
            warnings: warnings
        )
    }

    private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        min(max(value, minValue), maxValue)
    }
}
