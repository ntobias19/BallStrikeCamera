#if DEBUG
import Foundation

// VLAModelData and VLAModelPredictor (load/autoLoad/predict) are defined in
// Analysis/VLAModelPredictor.swift and available in all build configurations.

struct ExperimentalVLAModelPredictor {

    /// Extract features from ExperimentalBall3DObservation list for the trained VLA model.
    static func extractFeatures(
        from observations: [ExperimentalBall3DObservation],
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
#endif
