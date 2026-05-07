import Foundation

struct VLAModelData {
    let modelType: String
    let features: [String]
    let featureMeans: [String: Double]
    let featureStds: [String: Double]
    let imputationMedians: [String: Double]
    let coefficients: [String: Double]
    let intercept: Double
    let predictionClamp: (Double, Double)
    let trainingShots: Int
    let metrics: [String: Double]
    let featureSearchTopSubset: [String]
    let filePath: String
}

struct VLAModelPredictor {

    static let defaultModelPaths: [String] = [
        NSHomeDirectory() + "/Documents/vla_model.json",
        NSHomeDirectory() + "/Downloads/vla_model.json",
    ]

    static func load(from path: String) -> VLAModelData? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            print("[VLAModelPredictor] Failed to load: \(path)")
            return nil
        }
        guard
            let features     = json["features"] as? [String],
            let meansRaw     = json["featureMeans"] as? [String: Any],
            let stdsRaw      = json["featureStds"] as? [String: Any],
            let coefsRaw     = json["coefficients"] as? [String: Any],
            let intercept    = json["intercept"] as? Double
        else {
            print("[VLAModelPredictor] Invalid model JSON at \(path)")
            return nil
        }

        func toDoubleDict(_ d: [String: Any]) -> [String: Double] {
            d.compactMapValues { $0 as? Double }
        }

        let clampArr = json["predictionClamp"] as? [Double] ?? [0, 65]
        let clamp    = (clampArr.first ?? 0, clampArr.last ?? 65)
        let medians  = (json["imputationMedians"] as? [String: Any]).map(toDoubleDict) ?? [:]
        let metricsRaw = (json["metrics"] as? [String: Any]).map(toDoubleDict) ?? [:]
        let topSubset = json["featureSearchTopSubset"] as? [String] ?? []

        let model = VLAModelData(
            modelType: json["modelType"] as? String ?? "ridge_regression",
            features: features,
            featureMeans: toDoubleDict(meansRaw),
            featureStds: toDoubleDict(stdsRaw),
            imputationMedians: medians,
            coefficients: toDoubleDict(coefsRaw),
            intercept: intercept,
            predictionClamp: clamp,
            trainingShots: json["trainingShots"] as? Int ?? 0,
            metrics: metricsRaw,
            featureSearchTopSubset: topSubset,
            filePath: path
        )
        print(String(format: "[VLAModelPredictor] Loaded %@ n=%d MAE=%.2f°",
                     model.modelType, model.trainingShots, model.metrics["mae"] ?? 0))
        return model
    }

    static func autoLoad(overridePath: String? = nil) -> VLAModelData? {
        // Check app bundle first
        if let bundlePath = Bundle.main.path(forResource: "vla_model", ofType: "json", inDirectory: "Models"),
           let model = load(from: bundlePath) {
            return model
        }
        // Check app bundle root
        if let bundlePath = Bundle.main.path(forResource: "vla_model", ofType: "json"),
           let model = load(from: bundlePath) {
            return model
        }
        var paths = [String]()
        if let p = overridePath { paths.append(p) }
        paths.append(contentsOf: defaultModelPaths)
        for path in paths {
            if FileManager.default.fileExists(atPath: path),
               let model = load(from: path) {
                return model
            }
        }
        print("[VLAModelPredictor] No vla_model.json found in bundle or default locations")
        return nil
    }

    static func predict(
        features featureDict: [String: Double],
        model: VLAModelData
    ) -> (raw: Double, clamped: Double, featuresUsed: [String: Double], warnings: [String]) {
        var warnings = [String]()
        var featuresUsed = [String: Double]()
        var dot = 0.0

        for fn in model.features {
            var value: Double
            if let v = featureDict[fn], v.isFinite {
                value = v
            } else {
                let imputed = model.imputationMedians[fn] ?? 0.0
                warnings.append("Feature '\(fn)' missing — imputed \(String(format: "%.4f", imputed))")
                value = imputed
            }
            featuresUsed[fn] = value
            let mean = model.featureMeans[fn] ?? 0.0
            let std  = max(model.featureStds[fn] ?? 1.0, 1e-10)
            let z    = (value - mean) / std
            let coef = model.coefficients[fn] ?? 0.0
            dot += coef * z
        }

        let raw     = dot + model.intercept
        let clamped = min(max(raw, model.predictionClamp.0), model.predictionClamp.1)
        if abs(raw - clamped) > 0.01 {
            warnings.append(String(format: "Trained VLA %.1f° clamped to %.1f°", raw, clamped))
        }
        return (raw, clamped, featuresUsed, warnings)
    }

    static func extractFeatures(
        from observations: [Ball3DObservation],
        hlaDegrees: Double?,
        ballSpeedMph: Double?,
        impactFrameIndex: Int,
        totalFrames: Int
    ) -> [String: Double] {
        guard observations.count >= 2 else { return [:] }

        var feats = [String: Double]()

        let cxs  = observations.map { Double($0.imageX) }
        let cys  = observations.map { Double($0.imageY) }
        let dias = observations.map { Double($0.diameterNorm) }

        feats["n_valid_post_points"]  = Double(observations.count)
        feats["impact_frame"]         = Double(impactFrameIndex)
        feats["total_frames"]         = Double(totalFrames)
        if let hla = hlaDegrees {
            feats["hla_degrees"]      = hla
            feats["abs_hla_degrees"]  = abs(hla)
        }
        if let spd = ballSpeedMph { feats["ball_speed_mph"] = spd }

        feats["first_post_cx"]  = cxs.first!
        feats["first_post_cy"]  = cys.first!
        feats["first_post_dia"] = dias.first!
        feats["last_post_cx"]   = cxs.last!
        feats["last_post_cy"]   = cys.last!
        feats["last_post_dia"]  = dias.last!
        feats["max_center_x"]   = cxs.max()!
        feats["min_center_x"]   = cxs.min()!
        feats["center_x_range"] = cxs.max()! - cxs.min()!
        feats["max_diameter_norm"] = dias.max()!
        feats["min_diameter_norm"] = dias.min()!
        feats["mean_diameter_norm"] = dias.reduce(0, +) / Double(dias.count)

        let dxFl = cxs.last! - cxs.first!
        let dyFl = cys.last! - cys.first!
        feats["forward_progress_total"] = dxFl
        feats["dx_first_last"]          = dxFl
        feats["vertical_image_change_total"] = dyFl

        if dias.first! > 1e-6 {
            feats["diameter_growth_ratio"] = dias.last! / dias.first!
            feats["diameter_growth_ratio_squared"] = (dias.last! / dias.first!) * (dias.last! / dias.first!)
        }

        if dias.count >= 2 {
            let idx3 = min(2, dias.count - 1)
            feats["early_diameter_slope_1to3"] = (dias[idx3] - dias[0]) / Double(max(1, idx3))
        }

        let dts = zip(observations, observations.dropFirst()).map { $1.relativeTime - $0.relativeTime }
        let totalDt = dts.reduce(0, +)
        if totalDt > 1e-6 {
            feats["x_speed_norm"] = dxFl / totalDt
            feats["y_speed_norm"] = dyFl / totalDt
        }

        for pi in 1...min(3, observations.count) {
            let obs = observations[pi - 1]
            feats["p\(pi)_x"]        = Double(obs.imageX)
            feats["p\(pi)_y"]        = Double(obs.imageY)
            feats["p\(pi)_diameter"] = Double(obs.diameterNorm)
            feats["p\(pi)_confidence"] = obs.confidence
        }

        for wn in [2, 3, 5] {
            let pts = Array(observations.prefix(wn))
            guard pts.count >= 1 else { continue }
            let pf = "first\(wn)_"
            let wcxs  = pts.map { Double($0.imageX) }
            let wcys  = pts.map { Double($0.imageY) }
            let wdias = pts.map { Double($0.diameterNorm) }
            feats[pf + "mean_cx"]  = wcxs.reduce(0,+)  / Double(wcxs.count)
            feats[pf + "mean_cy"]  = wcys.reduce(0,+)  / Double(wcys.count)
            feats[pf + "mean_dia"] = wdias.reduce(0,+) / Double(wdias.count)
            if pts.count >= 2 {
                feats[pf + "x_progress"] = wcxs.last! - wcxs.first!
                feats[pf + "y_change"]   = wcys.last! - wcys.first!
                if wdias.first! > 1e-6 {
                    feats[pf + "diameter_growth_ratio"] = wdias.last! / wdias.first!
                }
            }
        }

        if let mcx = feats["first_post_cx"] {
            feats["mean_cx_times_mean_ground_ratio"] = mcx
        }

        return feats
    }
}
