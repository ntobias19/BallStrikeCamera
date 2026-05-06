import Foundation

struct DistanceEstimate {
    let idealCarryYards: Double?
    let carryCorrectionFactor: Double
    let carryYards: Double?
    let rolloutYards: Double?
    let totalYards: Double?
    let rolloutFraction: Double?
    let vlaBucket: String
    let method: String
    let warnings: [String]
}

struct DistanceEstimator {
    func estimate(
        ballSpeedMph: Double?,
        vlaDegrees: Double?,
        hlaDegrees: Double?,
        carryCorrectionFactor: Double = 0.75
    ) -> DistanceEstimate {
        var warnings = [String]()

        guard let ballSpeedMph, ballSpeedMph > 0 else {
            warnings.append("Distance estimate skipped: missing ball speed.")
            return DistanceEstimate(
                idealCarryYards: nil, carryCorrectionFactor: carryCorrectionFactor,
                carryYards: nil, rolloutYards: nil, totalYards: nil,
                rolloutFraction: nil, vlaBucket: "unknown",
                method: "unavailable", warnings: warnings)
        }
        guard let vlaDegrees, vlaDegrees.isFinite else {
            warnings.append("Distance estimate skipped: missing VLA.")
            return DistanceEstimate(
                idealCarryYards: nil, carryCorrectionFactor: carryCorrectionFactor,
                carryYards: nil, rolloutYards: nil, totalYards: nil,
                rolloutFraction: nil, vlaBucket: "unknown",
                method: "unavailable", warnings: warnings)
        }

        if hlaDegrees == nil {
            warnings.append("HLA unavailable; distance model ignores lateral curve.")
        }

        let clampedVLA = min(max(vlaDegrees, 0.5), 45)
        if clampedVLA != vlaDegrees {
            warnings.append(String(format: "VLA %.1f° clamped to %.1f° for distance estimate.", vlaDegrees, clampedVLA))
        }

        let speedMps = ballSpeedMph / 2.23694
        let vlaRad   = clampedVLA * .pi / 180.0
        let idealCarryMeters = (speedMps * speedMps * sin(2.0 * vlaRad)) / 9.80665
        let idealCarryYards  = idealCarryMeters * 1.09361

        let correctionFactor = clamp(carryCorrectionFactor, 0.40, 1.20)
        let carry = clamp(idealCarryYards * correctionFactor, 0, 450)

        let baseRollout: Double
        let vlaBucket: String
        if clampedVLA < 1 {
            baseRollout = 0.85; vlaBucket = "vla<1°"
        } else if clampedVLA < 3 {
            baseRollout = 0.65; vlaBucket = "1°≤vla<3°"
        } else if clampedVLA < 6 {
            baseRollout = 0.45; vlaBucket = "3°≤vla<6°"
        } else if clampedVLA < 10 {
            baseRollout = 0.30; vlaBucket = "6°≤vla<10°"
        } else if clampedVLA < 15 {
            baseRollout = 0.20; vlaBucket = "10°≤vla<15°"
        } else if clampedVLA < 22 {
            baseRollout = 0.12; vlaBucket = "15°≤vla<22°"
        } else if clampedVLA < 30 {
            baseRollout = 0.07; vlaBucket = "22°≤vla<30°"
        } else {
            baseRollout = 0.03; vlaBucket = "vla≥30°"
        }

        let speedAdjust: Double
        if ballSpeedMph < 40        { speedAdjust = 0.45 }
        else if ballSpeedMph < 80   { speedAdjust = 0.75 }
        else if ballSpeedMph >= 130 { speedAdjust = 1.10 }
        else                        { speedAdjust = 1.00 }

        let rolloutFraction = clamp(baseRollout * speedAdjust, 0.02, 0.90)
        let rolloutYards    = carry * rolloutFraction
        let total           = min(carry + rolloutYards, 400)

        if total > 350 {
            warnings.append("Total distance estimate >350 yd — verify calibration and FOV settings.")
        }
        warnings.append("Total = carry + VLA-based rollout. Spin and ground conditions unknown.")
        warnings.append(String(format: "Carry: idealCarry=%.0f yd × correctionFactor=%.2f = %.0f yd",
                               idealCarryYards, correctionFactor, carry))
        warnings.append(String(format: "Rollout: %.0f%% of carry (VLA bucket: %@)", rolloutFraction * 100, vlaBucket))

        return DistanceEstimate(
            idealCarryYards: idealCarryYards > 0 ? idealCarryYards : nil,
            carryCorrectionFactor: correctionFactor,
            carryYards: carry > 0 ? carry : nil,
            rolloutYards: rolloutYards > 0 ? rolloutYards : nil,
            totalYards: total > 0 ? total : nil,
            rolloutFraction: rolloutFraction,
            vlaBucket: vlaBucket,
            method: String(format: "physics_carry_cf%.2f_rollout%.0fpct_%@",
                           correctionFactor, rolloutFraction * 100, vlaBucket),
            warnings: warnings
        )
    }

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
