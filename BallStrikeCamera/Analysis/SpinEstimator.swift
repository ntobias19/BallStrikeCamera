import Foundation

struct SpinEstimate {
    let estimatedBackspinRpm: Double?
    let estimatedSidespinRpmSigned: Double?
    let estimatedSidespinDisplay: String
    let estimatedSpinAxisDegreesSigned: Double?
    let estimatedSpinAxisDisplay: String
    let spinEstimateMethod: String
    let warnings: [String]
}

struct SpinEstimator {
    func estimate(
        ballSpeedMph: Double?,
        vlaDegrees: Double?,
        hlaDegrees: Double?,
        clubPathDegrees: Double?
    ) -> SpinEstimate {
        var warnings: [String] = [
            "Backspin is ESTIMATED from a speed+VLA model. Not measured.",
            "Sidespin is ESTIMATED from HLA/path angle difference. Not measured."
        ]

        guard let ballSpeedMph, ballSpeedMph > 0 else {
            warnings.append("Spin estimate unavailable: missing ball speed.")
            return SpinEstimate(
                estimatedBackspinRpm: nil,
                estimatedSidespinRpmSigned: nil, estimatedSidespinDisplay: "—",
                estimatedSpinAxisDegreesSigned: nil, estimatedSpinAxisDisplay: "—",
                spinEstimateMethod: "unavailable", warnings: warnings
            )
        }

        let vla = vlaDegrees ?? 15.0
        if vlaDegrees == nil {
            warnings.append("VLA unavailable — backspin estimate uses default VLA=15°.")
        }

        let vlaMultiplier: Double
        if vla < 5       { vlaMultiplier = 0.60 }
        else if vla < 10 { vlaMultiplier = 0.80 }
        else if vla < 20 { vlaMultiplier = 1.00 }
        else if vla < 30 { vlaMultiplier = 1.20 }
        else             { vlaMultiplier = 1.35 }

        let rawBackspin = (800 + 90 * ballSpeedMph + 120 * vla) * vlaMultiplier
        let backspinRpm = min(max(rawBackspin, 300), 9000)

        let sidespinRpmSigned: Double?
        let spinAxisDegreesSigned: Double?
        let method: String

        if let hla = hlaDegrees, let path = clubPathDegrees {
            let faceToPath  = hla - path
            let speedFactor = ballSpeedMph / 100.0
            let sidespin    = min(max(faceToPath * 200.0 * speedFactor, -4000), 4000)
            sidespinRpmSigned     = sidespin
            spinAxisDegreesSigned = atan2(sidespin, backspinRpm) * 180.0 / .pi
            method = "backspin_speed_vla_model_sidespin_hla_minus_path"
        } else if let hla = hlaDegrees {
            let speedFactor = ballSpeedMph / 100.0
            let sidespin    = min(max(hla * 150.0 * speedFactor, -4000), 4000)
            sidespinRpmSigned     = sidespin
            spinAxisDegreesSigned = atan2(sidespin, backspinRpm) * 180.0 / .pi
            warnings.append("Club path unavailable — sidespin estimated from HLA only (lower accuracy).")
            method = "backspin_speed_vla_model_sidespin_hla_only"
        } else {
            sidespinRpmSigned     = nil
            spinAxisDegreesSigned = nil
            warnings.append("HLA unavailable — sidespin and spin axis unavailable.")
            method = "backspin_speed_vla_model_sidespin_unavailable"
        }

        let sidespinDisplay = sidespinRpmSigned.map    { DirectionalFormat.spinLR($0) } ?? "—"
        let spinAxisDisplay = spinAxisDegreesSigned.map { DirectionalFormat.angleLR($0) } ?? "—"

        return SpinEstimate(
            estimatedBackspinRpm: backspinRpm,
            estimatedSidespinRpmSigned: sidespinRpmSigned,
            estimatedSidespinDisplay: sidespinDisplay,
            estimatedSpinAxisDegreesSigned: spinAxisDegreesSigned,
            estimatedSpinAxisDisplay: spinAxisDisplay,
            spinEstimateMethod: method,
            warnings: warnings
        )
    }
}
