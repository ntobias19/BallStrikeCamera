import Foundation

private struct RidgeModel {
    let features: [String]
    let means: [String: Double]
    let stds: [String: Double]
    let imputationMedians: [String: Double]
    let coefficients: [String: Double]
    let intercept: Double

    func predict(inputs: [String: Double]) -> Double {
        var dot = intercept
        for fn in features {
            let value: Double
            if let v = inputs[fn], v.isFinite {
                value = v
            } else {
                value = imputationMedians[fn] ?? 0.0
            }
            let mean = means[fn] ?? 0.0
            let std  = max(stds[fn] ?? 1.0, 1e-10)
            let coef = coefficients[fn] ?? 0.0
            dot += coef * ((value - mean) / std)
        }
        return dot
    }
}

struct FlightModelPredictor {
    private let carryModel: RidgeModel
    private let rollModel: RidgeModel

    private init(carry: RidgeModel, roll: RidgeModel) {
        self.carryModel = carry
        self.rollModel  = roll
    }

    static func autoLoad() -> FlightModelPredictor? {
        guard let url = ModelResourceLoader.url(forModelResource: "flight_model") else {
            print("[FlightModelPredictor] flight_model.json not found")
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            print("[FlightModelPredictor] Failed to parse flight_model.json")
            return nil
        }
        guard let carry = parseModel(json["carryModel"]),
              let roll  = parseModel(json["rollModel"])
        else {
            print("[FlightModelPredictor] Invalid flight_model.json structure")
            return nil
        }
        if let metrics = json["metrics"] as? [String: Double] {
            print(String(format: "[FlightModelPredictor] Loaded — carry MAE=%.1f yd  total MAE=%.1f yd  n=%d",
                         metrics["carry_mae"] ?? 0,
                         metrics["total_mae"] ?? 0,
                         Int(metrics["n_shots"] ?? 0)))
        }
        return FlightModelPredictor(carry: carry, roll: roll)
    }

    private static func parseModel(_ raw: Any?) -> RidgeModel? {
        guard let dict = raw as? [String: Any] else { return nil }
        func doubles(_ key: String) -> [String: Double]? {
            (dict[key] as? [String: Any])?.compactMapValues { $0 as? Double }
        }
        guard
            let features = dict["features"] as? [String],
            let means    = doubles("means"),
            let stds     = doubles("stds"),
            let coefs    = doubles("coefficients"),
            let intercept = dict["intercept"] as? Double
        else { return nil }
        let medians = doubles("imputationMedians") ?? [:]
        return RidgeModel(features: features, means: means, stds: stds,
                          imputationMedians: medians, coefficients: coefs, intercept: intercept)
    }

    // MARK: - Public API

    func predictCarry(ballSpeedMph: Double, vlaDegrees: Double, idealCarryYards: Double) -> Double {
        let vlaRad = vlaDegrees * .pi / 180.0
        let inputs: [String: Double] = [
            "ball_speed":        ballSpeedMph,
            "vla":               vlaDegrees,
            "ball_speed_sq":     ballSpeedMph * ballSpeedMph,
            "vla_sq":            vlaDegrees * vlaDegrees,
            "speed_times_vla":   ballSpeedMph * vlaDegrees,
            "sin_2vla":          sin(2.0 * vlaRad),
            "ideal_carry_yards": idealCarryYards,
        ]
        let raw = carryModel.predict(inputs: inputs)
        return max(raw, 0)
    }

    func predictRollout(ballSpeedMph: Double, vlaDegrees: Double,
                        idealCarryYards: Double, carryYards: Double,
                        backspinRpm: Double?) -> Double {
        let vlaRad = vlaDegrees * .pi / 180.0
        var inputs: [String: Double] = [
            "ball_speed":        ballSpeedMph,
            "vla":               vlaDegrees,
            "ball_speed_sq":     ballSpeedMph * ballSpeedMph,
            "vla_sq":            vlaDegrees * vlaDegrees,
            "speed_times_vla":   ballSpeedMph * vlaDegrees,
            "sin_2vla":          sin(2.0 * vlaRad),
            "ideal_carry_yards": idealCarryYards,
            "carry_yards":       carryYards,
        ]
        if let rpm = backspinRpm, rpm.isFinite {
            inputs["backspin"] = rpm
        }
        let raw = rollModel.predict(inputs: inputs)
        return max(raw, 0)
    }
}
