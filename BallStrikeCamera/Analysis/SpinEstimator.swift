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
        clubPathDegrees: Double?,
        smashFactor: Double? = nil
    ) -> SpinEstimate {
        var warnings: [String] = [
            "Backspin is ESTIMATED from a VLA/speed/smash piecewise model. Not measured.",
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

        let baseSpin = piecewiseBackspin(vla: vla)

        let smashAdj: Double
        if let smash = smashFactor, smash > 0 {
            smashAdj = min(max(1.0 + (1.30 - smash) * 0.35, 0.75), 1.25)
        } else {
            smashAdj = 1.0
        }

        let speedAdj: Double
        if vla < 20.0 {
            speedAdj = min(max(1.0 - (ballSpeedMph - 70.0) * 0.003, 0.75), 1.15)
        } else {
            speedAdj = min(max(1.0 - (ballSpeedMph - 80.0) * 0.0015, 0.85), 1.15)
        }

        let backspinRpm = min(max(baseSpin * smashAdj * speedAdj, 1200), 11500)

        if smashAdj < 0.95 {
            warnings.append(String(format: "Backspin reduced by smash factor %.2f (adj=%.2f).", smashFactor ?? 0, smashAdj))
        }

        let sidespinRpmSigned: Double?
        let spinAxisDegreesSigned: Double?
        let method: String

        if let hla = hlaDegrees, let path = clubPathDegrees {
            let faceToPath  = hla - path
            let speedFactor = ballSpeedMph / 100.0
            let sidespin    = min(max(faceToPath * 200.0 * speedFactor, -4000), 4000)
            sidespinRpmSigned     = sidespin
            spinAxisDegreesSigned = atan2(sidespin, backspinRpm) * 180.0 / .pi
            method = "vla_speed_smash_piecewise_sidespin_hla_minus_path"
        } else if let hla = hlaDegrees {
            let speedFactor = ballSpeedMph / 100.0
            let sidespin    = min(max(hla * 150.0 * speedFactor, -4000), 4000)
            sidespinRpmSigned     = sidespin
            spinAxisDegreesSigned = atan2(sidespin, backspinRpm) * 180.0 / .pi
            warnings.append("Club path unavailable — sidespin estimated from HLA only (lower accuracy).")
            method = "vla_speed_smash_piecewise_sidespin_hla_only"
        } else {
            sidespinRpmSigned     = nil
            spinAxisDegreesSigned = nil
            warnings.append("HLA unavailable — sidespin and spin axis unavailable.")
            method = "vla_speed_smash_piecewise_sidespin_unavailable"
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

    private func piecewiseBackspin(vla: Double) -> Double {
        let table: [(Double, Double)] = [
            (0,  1800), (5,  2200), (10, 2600), (15, 3200), (20, 4200),
            (30, 5800), (40, 7200), (50, 8700), (60, 10500), (65, 11200)
        ]
        if vla <= table.first!.0 { return table.first!.1 }
        if vla >= table.last!.0  { return table.last!.1 }
        for i in 0..<(table.count - 1) {
            let (v0, s0) = table[i]
            let (v1, s1) = table[i + 1]
            if vla >= v0 && vla <= v1 {
                let t = (vla - v0) / (v1 - v0)
                return s0 + t * (s1 - s0)
            }
        }
        return 4200
    }
}
