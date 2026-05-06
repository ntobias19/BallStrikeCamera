import CoreGraphics

struct ImpactDetectionConfig {
    var movementThresholdNorm: CGFloat = 0.006
    var confirmFrames:         Int     = 2
    var stableWindowCount:     Int     = 10
    // Part A: diameter change detection
    var useDiameterChange:    Bool    = true
    var diameterChangeRatio:  CGFloat = 1.35
    var diameterShrinkRatio:  CGFloat = 0.80
    var returnOneFrameBefore: Bool    = true
    var minimumStableFrames:  Int     = 6
}

struct ImpactDetectionResult {
    let detectedImpactFrameIndex: Int
    let fallbackImpactFrameIndex: Int
    let impactDetectionReason:    String
    let initialBallCenter:        CGPoint?
    let movementThresholdNorm:    CGFloat
    let initialJitter:            CGFloat
}

struct ExperimentalImpactFrameDetector {
    let config: ImpactDetectionConfig

    func detect(
        observations: [BallTrackingTestObservation],
        fallbackImpactIndex: Int
    ) -> ImpactDetectionResult {

        print("Experimental impact detection")
        print("  Fallback impact frame: \(fallbackImpactIndex)")

        let windowSize  = max(3, config.stableWindowCount)
        let cutoff      = min(windowSize, fallbackImpactIndex)

        // Stable frames: tracked detections before the fallback impact, within the window
        let stableObs = observations
            .filter { $0.frameIndex < cutoff && $0.centerX != nil }
            .sorted { $0.frameIndex < $1.frameIndex }

        print("  Stable window: frames 0..<\(cutoff), found \(stableObs.count) tracked")

        let minStable = max(3, config.minimumStableFrames)
        guard stableObs.count >= minStable else {
            print("  Insufficient stable frames (\(stableObs.count), need \(minStable)) → fallback")
            return fallback(fallbackImpactIndex, center: nil, threshold: config.movementThresholdNorm,
                            jitter: 0, reason: "fallback_insufficient_stable_frames(\(stableObs.count))")
        }

        // Median center
        let cxs = stableObs.compactMap { $0.centerX }.sorted()
        let cys = stableObs.compactMap { $0.centerY }.sorted()
        let medCX = cxs[cxs.count / 2]
        let medCY = cys[cys.count / 2]
        let initialCenter = CGPoint(x: medCX, y: medCY)

        // Median diameter (for adaptive threshold)
        let dias = stableObs.compactMap { $0.diameter }.sorted()
        let medDia: CGFloat = dias.isEmpty ? 0.030 : dias[dias.count / 2]

        // Jitter (median displacement from median center)
        let jitters = stableObs.compactMap { obs -> CGFloat? in
            guard let cx = obs.centerX, let cy = obs.centerY else { return nil }
            return hypot(cx - medCX, cy - medCY)
        }.sorted()
        let jitter: CGFloat = jitters.isEmpty ? 0 : jitters[jitters.count / 2]

        // Effective threshold: larger of fixed norm or diameter-relative
        let threshold = max(config.movementThresholdNorm, medDia * 0.20)

        print(String(format: "  Initial center: x=%.4f y=%.4f", medCX, medCY))
        print(String(format: "  Initial jitter: %.4f", jitter))
        print(String(format: "  Median diameter: %.4f", medDia))
        print(String(format: "  Movement threshold: %.4f (config=%.4f)", threshold, config.movementThresholdNorm))

        // Scan all tracked frames after the stable window
        let scanStartFrame = stableObs.last.map { $0.frameIndex + 1 } ?? cutoff
        let scanObs = observations
            .filter { $0.frameIndex >= scanStartFrame && $0.centerX != nil }
            .sorted { $0.frameIndex < $1.frameIndex }

        print("  Scanning \(scanObs.count) frames for movement (from frame \(scanStartFrame))")

        var consecutiveCount = 0
        var firstMovingFrame: Int? = nil
        var lastFrameIdx = scanStartFrame - 2  // sentinel
        var eventFrame: Int? = nil
        var eventReason = "fallback_no_movement_detected"
        var diameterChangedFirst = false

        for obs in scanObs {
            guard let cx = obs.centerX, let cy = obs.centerY else {
                // bad detection — treat as event
                if eventFrame == nil {
                    eventFrame = obs.frameIndex
                    eventReason = "bad_detection_minus_one"
                }
                break
            }
            let displacement = hypot(cx - medCX, cy - medCY)
            let isConsec = (obs.frameIndex == lastFrameIdx + 1)

            // Position movement check
            if displacement > threshold {
                if consecutiveCount == 0 {
                    firstMovingFrame = obs.frameIndex
                    consecutiveCount = 1
                } else if isConsec {
                    consecutiveCount += 1
                } else {
                    // gap in sequence — restart from this frame
                    firstMovingFrame = obs.frameIndex
                    consecutiveCount = 1
                }
                if consecutiveCount >= config.confirmFrames, let first = firstMovingFrame {
                    print(String(format: "  Detected impact frame: %d (disp=%.4f, confirmed over %d frames)",
                                 first, displacement, consecutiveCount))
                    eventFrame = first
                    eventReason = "first_movement_minus_one"
                    break
                }
            } else {
                consecutiveCount = 0
                firstMovingFrame = nil
            }

            // Diameter change check (Part A)
            if config.useDiameterChange && !diameterChangedFirst && eventFrame == nil {
                if let dia = obs.diameter, medDia > 0 {
                    let diamRatio = dia / medDia
                    let diamSpiked = diamRatio > config.diameterChangeRatio
                    let diamShrunk = diamRatio < config.diameterShrinkRatio
                    if diamSpiked || diamShrunk {
                        eventFrame = obs.frameIndex
                        eventReason = diamSpiked ? "first_size_change_minus_one" : "first_size_shrink_minus_one"
                        diameterChangedFirst = true
                        break
                    }
                }
            }

            lastFrameIdx = obs.frameIndex
        }

        if let ef = eventFrame {
            let resultFrame = config.returnOneFrameBefore ? max(0, ef - 1) : ef
            print(String(format: "  Detected impact frame: %d (event=%d, reason=%@)",
                         resultFrame, ef, eventReason))
            return ImpactDetectionResult(
                detectedImpactFrameIndex: resultFrame,
                fallbackImpactFrameIndex: fallbackImpactIndex,
                impactDetectionReason:    eventReason,
                initialBallCenter:        initialCenter,
                movementThresholdNorm:    threshold,
                initialJitter:            jitter)
        }

        // Single-frame movement detected but not confirmed
        if let single = firstMovingFrame, config.confirmFrames <= 1 {
            print("  Detected impact frame: \(single) (unconfirmed, confirmFrames≤1)")
            print("  Impact detection reason: first_movement_unconfirmed")
            let resultFrame = config.returnOneFrameBefore ? max(0, single - 1) : single
            return ImpactDetectionResult(
                detectedImpactFrameIndex: resultFrame,
                fallbackImpactFrameIndex: fallbackImpactIndex,
                impactDetectionReason:    "first_movement_unconfirmed",
                initialBallCenter:        initialCenter,
                movementThresholdNorm:    threshold,
                initialJitter:            jitter)
        }

        print("  No confirmed movement → fallback to \(fallbackImpactIndex)")
        print("  Impact detection reason: \(eventReason)")
        return ImpactDetectionResult(
            detectedImpactFrameIndex: fallbackImpactIndex,
            fallbackImpactFrameIndex: fallbackImpactIndex,
            impactDetectionReason:    eventReason,
            initialBallCenter:        initialCenter,
            movementThresholdNorm:    threshold,
            initialJitter:            jitter)
    }

    private func fallback(
        _ idx: Int, center: CGPoint?, threshold: CGFloat,
        jitter: CGFloat, reason: String
    ) -> ImpactDetectionResult {
        ImpactDetectionResult(
            detectedImpactFrameIndex: idx,
            fallbackImpactFrameIndex: idx,
            impactDetectionReason:    reason,
            initialBallCenter:        center,
            movementThresholdNorm:    threshold,
            initialJitter:            jitter)
    }
}
