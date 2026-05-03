import UIKit
import CoreGraphics

final class PostImpactBallTracker {

    // MARK: - Configuration

    struct DiameterRefinementConfig {
        var enabled: Bool = true
        var localMaskWindowScale: CGFloat = 1.8
        var maskBrightnessThreshold: Int = 30
        // Kept for parity with the experimental settings object. The current tuned
        // mask path is brightness-only.
        var maskMaxChannelSpread: Int = 65
        var smoothingEnabled: Bool = true
        var smoothingWindowSize: Int = 5
    }

    struct ImpactDetectionConfiguration {
        var movementThresholdNorm: CGFloat = 0.006
        var confirmFrames: Int = 2
        var stableWindowCount: Int = 10
    }

    struct Configuration {
        var sampleStride: Int = 2

        var preBrightnessThreshold: Int = 90
        var preMaxChannelSpread: Int = 90
        var preMinBrightSamples: Int = 6
        var preMinNormWidth: CGFloat = 0.008
        var preMaxNormWidth: CGFloat = 0.090
        var preMinNormHeight: CGFloat = 0.012
        var preMaxNormHeight: CGFloat = 0.130
        var preMinAspect: CGFloat = 0.30
        var preMaxAspect: CGFloat = 2.00

        var postBrightnessThreshold: Int = 115
        var postMaxChannelSpread: Int = 110
        var postMinBrightSamples: Int = 4
        var postMinNormWidth: CGFloat = 0.005
        var postMaxNormWidth: CGFloat = 0.120
        var postMinNormHeight: CGFloat = 0.005
        var postMaxNormHeight: CGFloat = 0.150
        var postMinAspect: CGFloat = 0.12
        var postMaxAspect: CGFloat = 5.00

        var preImpactSearchScale: CGFloat = 5.67
        var impactSearchScale: CGFloat = 8.66
        var postImpactBaseScale: CGFloat = 5.03
        var postImpactScaleGrowth: CGFloat = 5.00
        var postImpactMaxScale: CGFloat = 30.0

        var diameterRefinement: DiameterRefinementConfig = DiameterRefinementConfig()
        var impactDetection: ImpactDetectionConfiguration = ImpactDetectionConfiguration()
        var isPostImpactDebugLoggingEnabled: Bool = true
    }

    struct TrackingResult {
        let observations: [ShotBallObservation]
        let debugInfos: [ShotFrameDebugInfo]
        let fallbackImpactFrameIndex: Int
        let detectedImpactFrameIndex: Int
        let impactDetectionReason: String
        let initialBallCenter: CGPoint?
        let movementThresholdNorm: CGFloat
    }

    private struct ImpactDetectionResult {
        let detectedImpactFrameIndex: Int
        let fallbackImpactFrameIndex: Int
        let impactDetectionReason: String
        let initialBallCenter: CGPoint?
        let movementThresholdNorm: CGFloat
        let initialJitter: CGFloat
    }

    private struct TrackingPassResult {
        let observations: [ShotBallObservation]
        let debugInfos: [ShotFrameDebugInfo]
    }

    private struct ScanConfig {
        let brightnessThreshold: Int
        let maxChannelSpread: Int
        let minimumBrightSamples: Int
        let minNormWidth: CGFloat
        let maxNormWidth: CGFloat
        let minNormHeight: CGFloat
        let maxNormHeight: CGFloat
        let minAspect: CGFloat
        let maxAspect: CGFloat
    }

    private struct RawBlob {
        var minX: Int
        var maxX: Int
        var minY: Int
        var maxY: Int
        var sumX: Int
        var sumY: Int
        var count: Int
    }

    private struct Candidate {
        let rect: CGRect
        let center: CGPoint
        let diameter: CGFloat
        let confidence: Double
        let accepted: Bool
        let rejectionReason: String?
        let brightPixelCount: Int
    }

    private struct MaskComponent {
        var indices: [Int]
        var minCol: Int
        var maxCol: Int
        var minRow: Int
        var maxRow: Int
        var distanceSquared: CGFloat

        var count: Int { indices.count }
    }

    private struct MaskRefineOutput {
        let diameter: CGFloat?
        let whitePixelCount: Int
        let reason: String
    }

    private let cfg: Configuration
    private var recentDiameters: [CGFloat] = []

    init(configuration: Configuration = Configuration()) {
        self.cfg = configuration
    }

    // MARK: - Public

    func track(
        frames: [AnalyzedShotFrame],
        lockedBallRect: CGRect,
        impactFrameIndex fallbackImpactFrameIndex: Int
    ) -> TrackingResult {
        logConfiguration()

        let pixelData: [(bytes: [UInt8], width: Int, height: Int)?] = frames.map {
            pixelBytes(from: $0.darkenedHighContrastImage ?? $0.originalFrame.image)
        }

        let preConfig = makeScanConfig(pre: true)
        let postConfig = makeScanConfig(pre: false)

        let firstPass = runTrackingPass(
            frames: frames,
            pixelData: pixelData,
            impactFrameIndex: fallbackImpactFrameIndex,
            lockedBallRect: lockedBallRect,
            preConfig: preConfig,
            postConfig: postConfig
        )

        let impactResult = detectImpact(
            observations: firstPass.observations,
            fallbackImpactIndex: fallbackImpactFrameIndex
        )

        let finalPass: TrackingPassResult
        if impactResult.detectedImpactFrameIndex != fallbackImpactFrameIndex {
            print("PostImpactBallTracker: re-tracking with detected impact frame \(impactResult.detectedImpactFrameIndex)")
            finalPass = runTrackingPass(
                frames: frames,
                pixelData: pixelData,
                impactFrameIndex: impactResult.detectedImpactFrameIndex,
                lockedBallRect: lockedBallRect,
                preConfig: preConfig,
                postConfig: postConfig
            )
        } else {
            finalPass = firstPass
        }

        let result = TrackingResult(
            observations: finalPass.observations,
            debugInfos: finalPass.debugInfos,
            fallbackImpactFrameIndex: impactResult.fallbackImpactFrameIndex,
            detectedImpactFrameIndex: impactResult.detectedImpactFrameIndex,
            impactDetectionReason: impactResult.impactDetectionReason,
            initialBallCenter: impactResult.initialBallCenter,
            movementThresholdNorm: impactResult.movementThresholdNorm
        )
        Self.printSummary(result)
        return result
    }

    static func printSummary(_ result: TrackingResult) {
        print("Live post-impact tracking complete")
        print("Fallback impact frame: \(result.fallbackImpactFrameIndex)")
        print("Detected impact frame: \(result.detectedImpactFrameIndex)")
        print("Impact detection reason: \(result.impactDetectionReason)")

        let impact = result.detectedImpactFrameIndex
        let observations = result.observations
        let preObs = observations.filter { $0.frameIndex < impact }
        let postObs = observations.filter { $0.frameIndex > impact }
        let tracked = observations.filter { $0.centerX != nil }
        let preTracked = preObs.filter { $0.centerX != nil }.count
        let postTracked = postObs.filter { $0.centerX != nil }.count

        print("Pre-impact tracked: \(preTracked)/\(preObs.count)")
        print("Post-impact tracked: \(postTracked)/\(postObs.count)")
        print("Total tracked: \(tracked.count)/\(observations.count)")

        let candidateDiameters = tracked.compactMap { $0.candidateDiameter }
        let refinedDiameters = tracked.compactMap { $0.refinedDiameter }
        let finalDiameters = tracked.compactMap { $0.finalDiameter ?? $0.diameter }
        let maskFailed = tracked.count - refinedDiameters.count

        print("Diameter refinement summary")
        print("Frames refined: \(refinedDiameters.count)")
        print("Mask failed: \(maskFailed)")
        print(String(format: "Average candidate diameter: %.4f", average(candidateDiameters)))
        print(String(format: "Average refined diameter: %.4f", average(refinedDiameters)))
        print(String(format: "Average final diameter: %.4f", average(finalDiameters)))

        print("--- Live per-frame tracking table ---")
        for obs in observations {
            let marker = obs.frameIndex == impact ? " <- impact" : ""
            if let cx = obs.centerX, let cy = obs.centerY, let d = obs.finalDiameter ?? obs.diameter {
                let cand = obs.candidateDiameter.map { String(format: "%.4f", $0) } ?? "n/a"
                let refined = obs.refinedDiameter.map { String(format: "%.4f", $0) } ?? "n/a"
                print(String(format: "frame=%02d t=%+.4f x=%.4f y=%.4f finalD=%.4f candD=%@ refinedD=%@ maskPx=%d reason=%@ conf=%.2f%@",
                             obs.frameIndex, obs.relativeTime, cx, cy, d, cand, refined,
                             obs.maskWhitePixelCount, obs.diameterDebugReason ?? "n/a",
                             obs.confidence, marker))
            } else {
                print(String(format: "frame=%02d t=%+.4f miss reason=%@%@",
                             obs.frameIndex, obs.relativeTime, obs.debugReason ?? "unknown", marker))
            }
        }
    }

    // Compatibility helper for older call sites.
    static func printSummary(_ observations: [ShotBallObservation], impactFrameIndex: Int) {
        let result = TrackingResult(
            observations: observations,
            debugInfos: [],
            fallbackImpactFrameIndex: impactFrameIndex,
            detectedImpactFrameIndex: impactFrameIndex,
            impactDetectionReason: "legacy_summary",
            initialBallCenter: nil,
            movementThresholdNorm: 0
        )
        printSummary(result)
    }

    // MARK: - Tracking Pass

    private func runTrackingPass(
        frames: [AnalyzedShotFrame],
        pixelData: [(bytes: [UInt8], width: Int, height: Int)?],
        impactFrameIndex: Int,
        lockedBallRect: CGRect,
        preConfig: ScanConfig,
        postConfig: ScanConfig
    ) -> TrackingPassResult {
        recentDiameters = []

        var observations: [ShotBallObservation] = []
        var debugInfos: [ShotFrameDebugInfo] = []
        var lastPreCenter = lockedBallRect.center
        var lastPostCenter: CGPoint?

        for (i, frame) in frames.enumerated() {
            let idx = frame.frameIndex
            guard i < pixelData.count, let pd = pixelData[i] else {
                observations.append(miss(frame, reason: "no_pixel_data"))
                debugInfos.append(ShotFrameDebugInfo(
                    frameIndex: idx,
                    searchROI: nil,
                    candidateCount: 0,
                    rejectionReason: "no_pixel_data",
                    searchCenterSource: "none",
                    searchScale: 0
                ))
                continue
            }

            if idx < impactFrameIndex {
                let roi = expanded(lockedBallRect, scale: cfg.preImpactSearchScale)
                let (candidates, chosen) = findCandidates(
                    pd,
                    roi: roi,
                    config: preConfig,
                    preferredCenter: lastPreCenter
                )
                let reason = chosen == nil ? firstRejectionReason(candidates) : nil
                if let c = chosen {
                    observations.append(makeHit(frame, c, pd: pd))
                    lastPreCenter = c.center
                } else {
                    observations.append(miss(frame, reason: reason ?? "no_candidate"))
                }
                debugInfos.append(ShotFrameDebugInfo(
                    frameIndex: idx,
                    searchROI: roi,
                    candidateCount: candidates.reduce(0) { $0 + $1.brightPixelCount },
                    rejectionReason: reason,
                    searchCenterSource: "lockedBall",
                    searchScale: cfg.preImpactSearchScale
                ))
            } else if idx == impactFrameIndex {
                let roi = expanded(lockedBallRect, scale: cfg.impactSearchScale)
                let (candidates, chosen) = findCandidates(
                    pd,
                    roi: roi,
                    config: preConfig,
                    preferredCenter: lastPreCenter
                )
                let reason = chosen == nil ? firstRejectionReason(candidates) : nil
                if let c = chosen {
                    observations.append(makeHit(frame, c, pd: pd))
                    lastPreCenter = c.center
                } else {
                    observations.append(miss(frame, reason: reason ?? "no_candidate"))
                }
                debugInfos.append(ShotFrameDebugInfo(
                    frameIndex: idx,
                    searchROI: roi,
                    candidateCount: candidates.reduce(0) { $0 + $1.brightPixelCount },
                    rejectionReason: reason,
                    searchCenterSource: "lockedBall",
                    searchScale: cfg.impactSearchScale
                ))
            } else {
                let result = trackPostImpact(
                    pd: pd,
                    frame: frame,
                    postOffset: idx - impactFrameIndex,
                    lockedBallRect: lockedBallRect,
                    lastPostCenter: lastPostCenter,
                    postConfig: postConfig
                )
                observations.append(result.observation)
                debugInfos.append(result.debugInfo)
                if let cx = result.observation.centerX, let cy = result.observation.centerY {
                    lastPostCenter = CGPoint(x: cx, y: cy)
                }
            }
        }

        return TrackingPassResult(observations: observations, debugInfos: debugInfos)
    }

    private func trackPostImpact(
        pd: (bytes: [UInt8], width: Int, height: Int),
        frame: AnalyzedShotFrame,
        postOffset: Int,
        lockedBallRect: CGRect,
        lastPostCenter: CGPoint?,
        postConfig: ScanConfig
    ) -> (observation: ShotBallObservation, debugInfo: ShotFrameDebugInfo) {
        let maxScale = min(
            cfg.postImpactMaxScale,
            cfg.postImpactBaseScale + CGFloat(postOffset) * cfg.postImpactScaleGrowth
        )
        let roiCenter = lastPostCenter ?? lockedBallRect.center
        let centerSource = lastPostCenter == nil ? "lockedBall_fallback" : "previousDetection"
        let scalePass1 = min(maxScale, max(cfg.postImpactBaseScale, maxScale * 0.5))
        let passes: [(roi: CGRect, scale: CGFloat)] = [
            (expandedAround(roiCenter, rect: lockedBallRect, scale: scalePass1), scalePass1),
            (expandedAround(roiCenter, rect: lockedBallRect, scale: maxScale), maxScale)
        ]

        var allCandidates: [Candidate] = []
        var chosen: Candidate?
        var usedROI = passes.last?.roi ?? .zero
        var usedScale = passes.last?.scale ?? maxScale

        for pass in passes {
            usedROI = pass.roi
            usedScale = pass.scale
            let (candidates, selected) = findCandidates(
                pd,
                roi: pass.roi,
                config: postConfig,
                preferredCenter: roiCenter
            )
            allCandidates = candidates
            if let selected {
                chosen = selected
                break
            }
        }

        if cfg.isPostImpactDebugLoggingEnabled {
            let roiStr = String(format: "(x=%.3f y=%.3f w=%.3f h=%.3f)",
                                usedROI.minX, usedROI.minY, usedROI.width, usedROI.height)
            if let chosen {
                print(String(format: "frame=%02d postROI=%@ selected=(x=%.4f y=%.4f d=%.4f conf=%.2f)",
                             frame.frameIndex, roiStr, chosen.center.x, chosen.center.y,
                             chosen.diameter, chosen.confidence))
            } else {
                print(String(format: "frame=%02d postROI=%@ selected=nil reason=%@ bright=%d",
                             frame.frameIndex, roiStr, firstRejectionReason(allCandidates),
                             allCandidates.reduce(0) { $0 + $1.brightPixelCount }))
            }
        }

        let reason = chosen == nil ? firstRejectionReason(allCandidates) : nil
        let observation = chosen.map { makeHit(frame, $0, pd: pd) }
            ?? miss(frame, reason: reason)
        let debugInfo = ShotFrameDebugInfo(
            frameIndex: frame.frameIndex,
            searchROI: usedROI,
            candidateCount: allCandidates.reduce(0) { $0 + $1.brightPixelCount },
            rejectionReason: reason,
            searchCenterSource: centerSource,
            searchScale: usedScale
        )
        return (observation, debugInfo)
    }

    // MARK: - Connected-Components Candidate Scanner

    private func findCandidates(
        _ pd: (bytes: [UInt8], width: Int, height: Int),
        roi: CGRect,
        config: ScanConfig,
        preferredCenter: CGPoint
    ) -> ([Candidate], Candidate?) {
        let (bytes, width, height) = pd
        let step = max(1, cfg.sampleStride)

        let xStart = max(0, Int(roi.minX * CGFloat(width)))
        let xEnd = min(width, Int(roi.maxX * CGFloat(width)))
        let yStart = max(0, Int(roi.minY * CGFloat(height)))
        let yEnd = min(height, Int(roi.maxY * CGFloat(height)))
        guard xEnd > xStart, yEnd > yStart else {
            return ([], nil)
        }

        let cols = (xEnd - xStart + step - 1) / step
        let rows = (yEnd - yStart + step - 1) / step
        var bright = [Bool](repeating: false, count: cols * rows)
        var visited = [Bool](repeating: false, count: cols * rows)

        for row in 0..<rows {
            let py = yStart + row * step
            let baseRow = py * width * 4
            for col in 0..<cols {
                let px = xStart + col * step
                let i = baseRow + px * 4
                let r = Int(bytes[i])
                let g = Int(bytes[i + 1])
                let b = Int(bytes[i + 2])
                let brightness = (r + g + b) / 3
                let spread = max(r, max(g, b)) - min(r, min(g, b))
                bright[row * cols + col] = brightness >= config.brightnessThreshold
                    && spread <= config.maxChannelSpread
            }
        }

        var blobs: [RawBlob] = []
        for startRow in 0..<rows {
            for startCol in 0..<cols {
                let startIndex = startRow * cols + startCol
                guard bright[startIndex], !visited[startIndex] else { continue }

                var blob = RawBlob(
                    minX: Int.max,
                    maxX: 0,
                    minY: Int.max,
                    maxY: 0,
                    sumX: 0,
                    sumY: 0,
                    count: 0
                )
                var queue = [startIndex]
                var head = 0
                visited[startIndex] = true

                while head < queue.count {
                    let index = queue[head]
                    head += 1
                    let col = index % cols
                    let row = index / cols
                    let px = xStart + col * step
                    let py = yStart + row * step

                    blob.count += 1
                    blob.sumX += px
                    blob.sumY += py
                    if px < blob.minX { blob.minX = px }
                    if px > blob.maxX { blob.maxX = px }
                    if py < blob.minY { blob.minY = py }
                    if py > blob.maxY { blob.maxY = py }

                    for offset in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let nextCol = col + offset.0
                        let nextRow = row + offset.1
                        guard nextCol >= 0, nextCol < cols, nextRow >= 0, nextRow < rows else {
                            continue
                        }
                        let nextIndex = nextRow * cols + nextCol
                        if bright[nextIndex], !visited[nextIndex] {
                            visited[nextIndex] = true
                            queue.append(nextIndex)
                        }
                    }
                }
                blobs.append(blob)
            }
        }

        let candidates = blobs.map {
            evaluateBlob($0, step: step, width: width, height: height, config: config)
        }
        let chosen = candidates
            .filter { $0.accepted }
            .min {
                hypot($0.center.x - preferredCenter.x, $0.center.y - preferredCenter.y)
                    < hypot($1.center.x - preferredCenter.x, $1.center.y - preferredCenter.y)
            }

        return (candidates, chosen)
    }

    private func evaluateBlob(
        _ blob: RawBlob,
        step: Int,
        width: Int,
        height: Int,
        config: ScanConfig
    ) -> Candidate {
        let cx = CGFloat(blob.sumX) / CGFloat(blob.count) / CGFloat(width)
        let cy = CGFloat(blob.sumY) / CGFloat(blob.count) / CGFloat(height)
        let boxWidth = CGFloat(blob.maxX - blob.minX + step)
        let boxHeight = CGFloat(blob.maxY - blob.minY + step)
        let normWidth = boxWidth / CGFloat(width)
        let normHeight = boxHeight / CGFloat(height)
        let aspect = normWidth / max(normHeight, 1e-6)
        let diameter = (normWidth + normHeight) / 2
        let rect = CGRect(
            x: CGFloat(blob.minX) / CGFloat(width),
            y: CGFloat(blob.minY) / CGFloat(height),
            width: normWidth,
            height: normHeight
        )
        let confidence = min(1.0, Double(blob.count) / Double(config.minimumBrightSamples * 4))

        let reason: String?
        if blob.count < config.minimumBrightSamples {
            reason = "too_few_pixels(\(blob.count)<\(config.minimumBrightSamples))"
        } else if normWidth < config.minNormWidth {
            reason = "w_small(\(String(format: "%.4f", normWidth)))"
        } else if normWidth > config.maxNormWidth {
            reason = "w_large(\(String(format: "%.4f", normWidth)))"
        } else if normHeight < config.minNormHeight {
            reason = "h_small(\(String(format: "%.4f", normHeight)))"
        } else if normHeight > config.maxNormHeight {
            reason = "h_large(\(String(format: "%.4f", normHeight)))"
        } else if aspect < config.minAspect {
            reason = "asp_low(\(String(format: "%.2f", aspect)))"
        } else if aspect > config.maxAspect {
            reason = "asp_high(\(String(format: "%.2f", aspect)))"
        } else {
            reason = nil
        }

        return Candidate(
            rect: rect,
            center: CGPoint(x: cx, y: cy),
            diameter: diameter,
            confidence: reason == nil ? confidence : 0,
            accepted: reason == nil,
            rejectionReason: reason,
            brightPixelCount: blob.count
        )
    }

    // MARK: - Diameter Refinement

    private func makeHit(
        _ frame: AnalyzedShotFrame,
        _ candidate: Candidate,
        pd: (bytes: [UInt8], width: Int, height: Int)
    ) -> ShotBallObservation {
        let candidateDiameter = candidate.diameter
        let maskOutput = cfg.diameterRefinement.enabled
            ? maskRefineDiameter(
                pd,
                center: candidate.center,
                candidateDiameter: candidateDiameter,
                config: cfg.diameterRefinement
            )
            : MaskRefineOutput(diameter: nil, whitePixelCount: 0, reason: "refinement_disabled")

        let baseDiameter = maskOutput.diameter ?? candidateDiameter
        recentDiameters.append(baseDiameter)
        let windowSize = max(2, cfg.diameterRefinement.smoothingWindowSize)
        if recentDiameters.count > windowSize {
            recentDiameters.removeFirst()
        }

        let smoothedDiameter: CGFloat?
        if cfg.diameterRefinement.smoothingEnabled, recentDiameters.count >= 2 {
            smoothedDiameter = median(recentDiameters)
        } else {
            smoothedDiameter = nil
        }

        let finalDiameter = smoothedDiameter ?? maskOutput.diameter ?? candidateDiameter
        let diameterReason: String
        if smoothedDiameter != nil {
            diameterReason = "smoothed"
        } else if maskOutput.diameter != nil {
            diameterReason = maskOutput.reason
        } else if cfg.diameterRefinement.enabled {
            diameterReason = maskOutput.reason
        } else {
            diameterReason = "candidate_no_refinement"
        }

        return ShotBallObservation(
            frameIndex: frame.frameIndex,
            timestamp: frame.timestamp,
            relativeTime: frame.relativeTime,
            centerX: candidate.center.x,
            centerY: candidate.center.y,
            diameter: finalDiameter,
            candidateDiameter: candidateDiameter,
            refinedDiameter: maskOutput.diameter,
            smoothedDiameter: smoothedDiameter,
            finalDiameter: finalDiameter,
            confidence: candidate.confidence,
            wasInterpolated: false,
            debugReason: "ok",
            diameterDebugReason: diameterReason,
            maskWhitePixelCount: maskOutput.whitePixelCount
        )
    }

    private func maskRefineDiameter(
        _ pd: (bytes: [UInt8], width: Int, height: Int),
        center: CGPoint,
        candidateDiameter: CGFloat,
        config: DiameterRefinementConfig
    ) -> MaskRefineOutput {
        let (bytes, width, height) = pd
        let cx = Int((center.x * CGFloat(width)).rounded())
        let cy = Int((center.y * CGFloat(height)).rounded())
        guard cx >= 0, cx < width, cy >= 0, cy < height else {
            return MaskRefineOutput(
                diameter: nil,
                whitePixelCount: 0,
                reason: "mask_failed_center_oob"
            )
        }

        let radiusPx = max(
            4,
            Int((config.localMaskWindowScale * candidateDiameter * CGFloat(width) / 2).rounded())
        )
        let cropSize = radiusPx * 2 + 1
        let cropOriginX = cx - radiusPx
        let cropOriginY = cy - radiusPx

        let x0 = max(0, cx - radiusPx)
        let x1 = min(width - 1, cx + radiusPx)
        let y0 = max(0, cy - radiusPx)
        let y1 = min(height - 1, cy + radiusPx)

        var thresholdMask = [Bool](repeating: false, count: cropSize * cropSize)
        for py in y0...y1 {
            for px in x0...x1 {
                let col = px - cropOriginX
                let row = py - cropOriginY
                guard col >= 0, col < cropSize, row >= 0, row < cropSize else { continue }

                let pixelIndex = py * width * 4 + px * 4
                let r = Int(bytes[pixelIndex])
                let g = Int(bytes[pixelIndex + 1])
                let b = Int(bytes[pixelIndex + 2])
                let brightness = (r + g + b) / 3
                thresholdMask[row * cropSize + col] = brightness >= config.maskBrightnessThreshold
            }
        }

        let selection = mainMaskComponent(
            in: thresholdMask,
            cropSize: cropSize,
            targetCol: cx - cropOriginX,
            targetRow: cy - cropOriginY,
            maxCenterDriftPx: max(2, candidateDiameter * CGFloat(width) * 0.55)
        )

        guard let component = selection.component else {
            return MaskRefineOutput(
                diameter: nil,
                whitePixelCount: 0,
                reason: selection.failureReason
            )
        }

        let bboxWidthPx = component.maxCol - component.minCol + 1
        let bboxHeightPx = component.maxRow - component.minRow + 1
        let diameterPx = max(bboxWidthPx, bboxHeightPx)
        let refinedDiameter = CGFloat(diameterPx) / CGFloat(width)

        return MaskRefineOutput(
            diameter: refinedDiameter,
            whitePixelCount: component.count,
            reason: "mask_refined_threshold_\(config.maskBrightnessThreshold)_connected"
        )
    }

    private func mainMaskComponent(
        in mask: [Bool],
        cropSize: Int,
        targetCol: Int,
        targetRow: Int,
        maxCenterDriftPx: CGFloat
    ) -> (component: MaskComponent?, failureReason: String) {
        guard cropSize > 0, mask.count == cropSize * cropSize else {
            return (nil, "mask_failed_invalid_crop")
        }

        var visited = [Bool](repeating: false, count: mask.count)
        var components: [MaskComponent] = []

        for startIndex in mask.indices {
            guard mask[startIndex], !visited[startIndex] else { continue }

            var queue = [startIndex]
            var head = 0
            var indices: [Int] = []
            var minCol = Int.max
            var maxCol = 0
            var minRow = Int.max
            var maxRow = 0
            visited[startIndex] = true

            while head < queue.count {
                let index = queue[head]
                head += 1
                indices.append(index)

                let col = index % cropSize
                let row = index / cropSize
                if col < minCol { minCol = col }
                if col > maxCol { maxCol = col }
                if row < minRow { minRow = row }
                if row > maxRow { maxRow = row }

                for offset in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nextCol = col + offset.0
                    let nextRow = row + offset.1
                    guard nextCol >= 0, nextCol < cropSize, nextRow >= 0, nextRow < cropSize else {
                        continue
                    }
                    let nextIndex = nextRow * cropSize + nextCol
                    if mask[nextIndex], !visited[nextIndex] {
                        visited[nextIndex] = true
                        queue.append(nextIndex)
                    }
                }
            }

            let centerCol = CGFloat(minCol + maxCol) / 2
            let centerRow = CGFloat(minRow + maxRow) / 2
            let dx = centerCol - CGFloat(targetCol)
            let dy = centerRow - CGFloat(targetRow)
            components.append(MaskComponent(
                indices: indices,
                minCol: minCol,
                maxCol: maxCol,
                minRow: minRow,
                maxRow: maxRow,
                distanceSquared: dx * dx + dy * dy
            ))
        }

        guard !components.isEmpty else {
            return (nil, "mask_failed_no_white_pixels")
        }

        let substantial = components.filter { $0.count >= 3 }
        let usable = substantial.isEmpty ? components : substantial
        guard let selected = usable.min(by: {
            if $0.distanceSquared == $1.distanceSquared {
                return $0.count > $1.count
            }
            return $0.distanceSquared < $1.distanceSquared
        }) else {
            return (nil, "mask_failed_no_white_pixels")
        }

        guard sqrt(selected.distanceSquared) <= maxCenterDriftPx else {
            return (nil, "mask_failed_component_drift_fallback_candidate")
        }

        return (selected, "")
    }

    // MARK: - Dynamic Impact Detection

    private func detectImpact(
        observations: [ShotBallObservation],
        fallbackImpactIndex: Int
    ) -> ImpactDetectionResult {
        print("PostImpactBallTracker dynamic impact detection")
        print("  Fallback impact frame: \(fallbackImpactIndex)")

        let windowSize = max(3, cfg.impactDetection.stableWindowCount)
        let cutoff = min(windowSize, fallbackImpactIndex)
        let stableObs = observations
            .filter { $0.frameIndex < cutoff && $0.centerX != nil }
            .sorted { $0.frameIndex < $1.frameIndex }

        print("  Stable window: frames 0..<\(cutoff), found \(stableObs.count) tracked")

        guard stableObs.count >= 3 else {
            print("  Insufficient stable frames (\(stableObs.count)) - fallback")
            return fallbackImpact(
                fallbackImpactIndex,
                center: nil,
                threshold: cfg.impactDetection.movementThresholdNorm,
                jitter: 0,
                reason: "fallback_insufficient_stable_frames(\(stableObs.count))"
            )
        }

        let centersX = stableObs.compactMap { $0.centerX }.sorted()
        let centersY = stableObs.compactMap { $0.centerY }.sorted()
        let medianX = centersX[centersX.count / 2]
        let medianY = centersY[centersY.count / 2]
        let initialCenter = CGPoint(x: medianX, y: medianY)

        let diameters = stableObs.compactMap { $0.finalDiameter ?? $0.diameter }.sorted()
        let medianDiameter = diameters.isEmpty ? 0.030 : diameters[diameters.count / 2]

        let jitters = stableObs.compactMap { observation -> CGFloat? in
            guard let cx = observation.centerX, let cy = observation.centerY else { return nil }
            return hypot(cx - medianX, cy - medianY)
        }.sorted()
        let jitter = jitters.isEmpty ? 0 : jitters[jitters.count / 2]
        let threshold = max(cfg.impactDetection.movementThresholdNorm, medianDiameter * 0.20)

        print(String(format: "  Initial center: x=%.4f y=%.4f", medianX, medianY))
        print(String(format: "  Initial jitter: %.4f", jitter))
        print(String(format: "  Median diameter: %.4f", medianDiameter))
        print(String(format: "  Movement threshold: %.4f (config=%.4f)",
                     threshold, cfg.impactDetection.movementThresholdNorm))

        let scanStartFrame = stableObs.last.map { $0.frameIndex + 1 } ?? cutoff
        let scanObs = observations
            .filter { $0.frameIndex >= scanStartFrame && $0.centerX != nil }
            .sorted { $0.frameIndex < $1.frameIndex }

        var consecutiveCount = 0
        var firstMovingFrame: Int?
        var lastFrameIndex = scanStartFrame - 2

        for observation in scanObs {
            guard let cx = observation.centerX, let cy = observation.centerY else {
                consecutiveCount = 0
                firstMovingFrame = nil
                continue
            }

            let displacement = hypot(cx - medianX, cy - medianY)
            let isConsecutive = observation.frameIndex == lastFrameIndex + 1

            if displacement > threshold {
                if consecutiveCount == 0 {
                    firstMovingFrame = observation.frameIndex
                    consecutiveCount = 1
                } else if isConsecutive {
                    consecutiveCount += 1
                } else {
                    firstMovingFrame = observation.frameIndex
                    consecutiveCount = 1
                }

                if consecutiveCount >= cfg.impactDetection.confirmFrames,
                   let firstMovingFrame {
                    print(String(format: "  Detected impact frame: %d (disp=%.4f, confirmed over %d frames)",
                                 firstMovingFrame, displacement, consecutiveCount))
                    return ImpactDetectionResult(
                        detectedImpactFrameIndex: firstMovingFrame,
                        fallbackImpactFrameIndex: fallbackImpactIndex,
                        impactDetectionReason: "first_movement",
                        initialBallCenter: initialCenter,
                        movementThresholdNorm: threshold,
                        initialJitter: jitter
                    )
                }
            } else {
                consecutiveCount = 0
                firstMovingFrame = nil
            }

            lastFrameIndex = observation.frameIndex
        }

        if let firstMovingFrame, cfg.impactDetection.confirmFrames <= 1 {
            return ImpactDetectionResult(
                detectedImpactFrameIndex: firstMovingFrame,
                fallbackImpactFrameIndex: fallbackImpactIndex,
                impactDetectionReason: "first_movement_unconfirmed",
                initialBallCenter: initialCenter,
                movementThresholdNorm: threshold,
                initialJitter: jitter
            )
        }

        print("  No confirmed movement - fallback to \(fallbackImpactIndex)")
        return ImpactDetectionResult(
            detectedImpactFrameIndex: fallbackImpactIndex,
            fallbackImpactFrameIndex: fallbackImpactIndex,
            impactDetectionReason: "fallback_no_movement_detected",
            initialBallCenter: initialCenter,
            movementThresholdNorm: threshold,
            initialJitter: jitter
        )
    }

    private func fallbackImpact(
        _ index: Int,
        center: CGPoint?,
        threshold: CGFloat,
        jitter: CGFloat,
        reason: String
    ) -> ImpactDetectionResult {
        ImpactDetectionResult(
            detectedImpactFrameIndex: index,
            fallbackImpactFrameIndex: index,
            impactDetectionReason: reason,
            initialBallCenter: center,
            movementThresholdNorm: threshold,
            initialJitter: jitter
        )
    }

    // MARK: - Helpers

    private func miss(_ frame: AnalyzedShotFrame, reason: String? = "no_candidate") -> ShotBallObservation {
        ShotBallObservation(
            frameIndex: frame.frameIndex,
            timestamp: frame.timestamp,
            relativeTime: frame.relativeTime,
            centerX: nil,
            centerY: nil,
            diameter: nil,
            confidence: 0,
            wasInterpolated: false,
            debugReason: reason,
            diameterDebugReason: nil,
            maskWhitePixelCount: 0
        )
    }

    private func firstRejectionReason(_ candidates: [Candidate]) -> String {
        candidates.first(where: { !$0.accepted })?.rejectionReason
            ?? (candidates.isEmpty ? "no_blobs" : "no_accepted_candidate")
    }

    private func makeScanConfig(pre: Bool) -> ScanConfig {
        if pre {
            return ScanConfig(
                brightnessThreshold: cfg.preBrightnessThreshold,
                maxChannelSpread: cfg.preMaxChannelSpread,
                minimumBrightSamples: cfg.preMinBrightSamples,
                minNormWidth: cfg.preMinNormWidth,
                maxNormWidth: cfg.preMaxNormWidth,
                minNormHeight: cfg.preMinNormHeight,
                maxNormHeight: cfg.preMaxNormHeight,
                minAspect: cfg.preMinAspect,
                maxAspect: cfg.preMaxAspect
            )
        }

        return ScanConfig(
            brightnessThreshold: cfg.postBrightnessThreshold,
            maxChannelSpread: cfg.postMaxChannelSpread,
            minimumBrightSamples: cfg.postMinBrightSamples,
            minNormWidth: cfg.postMinNormWidth,
            maxNormWidth: cfg.postMaxNormWidth,
            minNormHeight: cfg.postMinNormHeight,
            maxNormHeight: cfg.postMaxNormHeight,
            minAspect: cfg.postMinAspect,
            maxAspect: cfg.postMaxAspect
        )
    }

    private func logConfiguration() {
        print(String(format: "PostImpactBallTracker live config: sampleStride=%d preBrightnessThreshold=%d preMaxChannelSpread=%d preMinBrightSamples=%d postBrightnessThreshold=%d postMaxChannelSpread=%d postMinBrightSamples=%d preImpactSearchScale=%.2f impactSearchScale=%.2f postImpactBaseScale=%.2f postImpactScaleGrowth=%.2f postImpactMaxScale=%.2f maskBrightnessThreshold=%d localMaskWindowScale=%.2f smoothingWindow=%d",
                     cfg.sampleStride,
                     cfg.preBrightnessThreshold,
                     cfg.preMaxChannelSpread,
                     cfg.preMinBrightSamples,
                     cfg.postBrightnessThreshold,
                     cfg.postMaxChannelSpread,
                     cfg.postMinBrightSamples,
                     cfg.preImpactSearchScale,
                     cfg.impactSearchScale,
                     cfg.postImpactBaseScale,
                     cfg.postImpactScaleGrowth,
                     cfg.postImpactMaxScale,
                     cfg.diameterRefinement.maskBrightnessThreshold,
                     cfg.diameterRefinement.localMaskWindowScale,
                     cfg.diameterRefinement.smoothingWindowSize))
        print("PostImpactBallTracker analysis mode: DarkenedHighContrast")
    }

    private func pixelBytes(from image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else { return nil }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return (bytes, width, height)
    }

    private func expanded(_ rect: CGRect, scale: CGFloat) -> CGRect {
        expandedAround(rect.center, rect: rect, scale: scale)
    }

    private func expandedAround(_ center: CGPoint, rect: CGRect, scale: CGFloat) -> CGRect {
        let width = rect.width * scale
        let height = rect.height * scale
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
        .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func average(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / CGFloat(values.count)
    }

    private func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
