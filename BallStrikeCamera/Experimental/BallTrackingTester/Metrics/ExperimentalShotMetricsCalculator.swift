#if DEBUG
import Foundation
import UIKit
import simd

struct ExperimentalShotMetricsCalculator {
    struct Configuration {
        var minimumBallPoints: Int = 2
        var preferredBallPointLimit: Int = 6
        var minimumClubPoints: Int = 2
        var lowConfidenceWarningThreshold: Double = 0.45
    }

    let configuration: Configuration
    let distanceEstimator  = ExperimentalDistanceEstimator()
    let spinEstimator      = ExperimentalSpinEstimator()
    let clubPathFaceEstimator = ExperimentalClubPathFaceEstimator()

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func calculate(
        sequence: BallTrackingTestSequence,
        ballResult: BallTrackingTestResult,
        calibrationSettings: CalibrationTuningSettings,
        clubConfiguration: ExperimentalClubTracker.Configuration,
        zeroDegreeAngleDegrees: Double = 0.0,
        carryCorrectionFactor: Double = 0.75
    ) -> ExperimentalShotMetricsResult? {
        print("Experimental metrics calculation started")
        guard let cg = sequence.frames.first?.image.cgImage else {
            print("Experimental metrics skipped: no image dimensions")
            return nil
        }

        let calibration = ExperimentalCameraCalibration.from(
            settings: calibrationSettings,
            imageWidth: cg.width,
            imageHeight: cg.height
        )
        print(String(format: "Experimental calibration: fovX=%.1f fovY=%.1f fx=%.1f fy=%.1f ballDiameter=%.5f",
                     calibration.horizontalFOVDegrees,
                     calibration.verticalFOVDegrees,
                     calibration.focalLengthPixelsX,
                     calibration.focalLengthPixelsY,
                     calibration.realBallDiameterMeters))

        let clubMode = clubConfiguration.useFrameDifference ? "frameDifference" : "dark_only"
        print("Experimental club tracking mode: \(clubMode)")

        let frameMap = Dictionary(uniqueKeysWithValues: sequence.frames.map { ($0.frameIndex, $0) })
        let ball3D = ballResult.observations.compactMap { observation -> ExperimentalBall3DObservation? in
            guard let frame = frameMap[observation.frameIndex] else { return nil }
            return calibration.ballObservation3D(from: observation, frame: frame)
        }

        let clubObservations = ExperimentalClubTracker(configuration: clubConfiguration)
            .track(sequence: sequence, ballResult: ballResult)

        let ballLaunch = calculateBallLaunch(
            ball3DObservations: ball3D,
            impactFrameIndex: ballResult.detectedImpactFrameIndex,
            zeroDegreeAngleDegrees: zeroDegreeAngleDegrees,
            calibration: calibration
        )
        let clubMetrics = calculateClubMetrics(
            clubObservations: clubObservations,
            ball3DObservations: ball3D,
            calibration: calibration,
            impactFrameIndex: ballResult.detectedImpactFrameIndex
        )

        let smashFactor: Double?
        if let ballSpeed = ballLaunch.ballSpeedMph,
           let clubSpeed = clubMetrics.clubSpeedMph,
           clubSpeed > 0 {
            smashFactor = ballSpeed / clubSpeed
        } else {
            smashFactor = nil
        }

        // Club path + face angle
        let clubPath = clubPathFaceEstimator.estimateClubPath(
            clubObservations: clubObservations,
            zeroDegreeAngleDegrees: zeroDegreeAngleDegrees,
            calibration: calibration,
            impactFrameIndex: ballResult.detectedImpactFrameIndex
        )

        let impactFrame = frameMap[ballResult.detectedImpactFrameIndex]?.image
        let faceAngle = clubPathFaceEstimator.estimateFaceAngle(
            clubObservations: clubObservations,
            impactFrame: impactFrame,
            zeroDegreeAngleDegrees: zeroDegreeAngleDegrees,
            calibration: calibration,
            impactFrameIndex: ballResult.detectedImpactFrameIndex,
            clubPathDegrees: clubPath.clubPathDegreesSigned
        )

        // Spin
        let spin = spinEstimator.estimate(
            ballSpeedMph: ballLaunch.ballSpeedMph,
            vlaDegrees: ballLaunch.vlaDegrees,
            hlaDegrees: ballLaunch.hlaDegrees,
            clubPathDegrees: clubPath.clubPathDegreesSigned
        )

        // Distance
        let distance = distanceEstimator.estimate(
            ballSpeedMph: ballLaunch.ballSpeedMph,
            vlaDegrees: ballLaunch.vlaDegrees,
            hlaDegrees: ballLaunch.hlaDegrees,
            carryCorrectionFactor: carryCorrectionFactor
        )

        var warnings = [
            "Experimental FOV calibration is estimated; tune calibration before trusting metrics."
        ]
        warnings.append(contentsOf: ballLaunch.warnings)
        warnings.append(contentsOf: clubMetrics.warnings)
        warnings.append(contentsOf: distance.warnings)
        warnings.append(contentsOf: spin.warnings)
        warnings.append(contentsOf: clubPath.warnings)
        warnings.append(contentsOf: faceAngle.warnings)
        if smashFactor == nil {
            warnings.append("Smash factor unavailable until ball speed and club speed are both available.")
        }

        let result = ExperimentalShotMetricsResult(
            detectedImpactFrameIndex: ballResult.detectedImpactFrameIndex,
            fallbackImpactFrameIndex: ballResult.fallbackImpactFrameIndex,
            calibration: calibration,
            zeroDegreeReferenceAngleDegrees: zeroDegreeAngleDegrees,
            ballLaunch: ballLaunch,
            club: clubMetrics,
            smashFactor: smashFactor,
            distance: distance,
            spin: spin,
            clubPath: clubPath,
            faceAngle: faceAngle,
            ball3DObservations: ball3D,
            clubObservations: clubObservations,
            warnings: Array(Set(warnings)).sorted()
        )

        printSummary(result)
        return result
    }

    // MARK: - Ball launch

    private func calculateBallLaunch(
        ball3DObservations: [ExperimentalBall3DObservation],
        impactFrameIndex: Int,
        zeroDegreeAngleDegrees: Double,
        calibration: ExperimentalCameraCalibration
    ) -> ExperimentalBallLaunchMetrics {
        var warnings: [String] = []
        let selected = Array(
            ball3DObservations
                .filter { $0.frameIndex > impactFrameIndex }
                .sorted { $0.frameIndex < $1.frameIndex }
                .prefix(configuration.preferredBallPointLimit)
        )

        guard selected.count >= configuration.minimumBallPoints else {
            warnings.append("Not enough post-impact ball points for speed/HLA/VLA.")
            return ExperimentalBallLaunchMetrics(
                ballSpeedMph: nil, hlaDegrees: nil, hlaDisplay: "—",
                hla3DRawDegrees: nil,
                vlaDegrees: nil, hlaReferenceAngleDegrees: zeroDegreeAngleDegrees,
                ballMovementDx: nil, ballMovementDy: nil,
                hlaForwardComponent: nil, hlaLateralComponent: nil,
                pointsUsed: selected.count, quality: 0,
                method: "not_enough_data", warnings: warnings
            )
        }

        let velocity: SIMD3<Double>?
        let method: String
        if selected.count >= 3 {
            velocity = linearFitVelocity(selected.map { ($0.relativeTime, $0.positionMeters) })
            method = "linear_fit_\(selected.count)_points"
        } else {
            let dt = selected[1].relativeTime - selected[0].relativeTime
            velocity = dt > 0 ? (selected[1].positionMeters - selected[0].positionMeters) / dt : nil
            method = "two_point_delta"
            warnings.append("Ball velocity used 2-point fallback.")
        }

        guard let velocity else {
            warnings.append("Ball velocity calculation failed due to invalid time span.")
            return ExperimentalBallLaunchMetrics(
                ballSpeedMph: nil, hlaDegrees: nil, hlaDisplay: "—",
                hla3DRawDegrees: nil,
                vlaDegrees: nil, hlaReferenceAngleDegrees: zeroDegreeAngleDegrees,
                ballMovementDx: nil, ballMovementDy: nil,
                hlaForwardComponent: nil, hlaLateralComponent: nil,
                pointsUsed: selected.count, quality: 0,
                method: method, warnings: warnings
            )
        }

        let speed = vectorLength(velocity)
        let ballSpeedMph = speed * 2.23694
        let hla3D = atan2(velocity.x, velocity.z) * 180 / .pi
        let horizontal = sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
        let vla = atan2(velocity.y, horizontal) * 180 / .pi

        let imageHLA = computeImageSpaceHLA(observations: selected,
                                            zeroDegreeAngleDegrees: zeroDegreeAngleDegrees,
                                            calibration: calibration)
        warnings.append(contentsOf: imageHLA.warnings)

        let hlaDisplay: String
        if let hla = imageHLA.hla {
            hlaDisplay = ExperimentalDirectionalFormat.angleLR(hla)
        } else {
            hlaDisplay = "—"
        }

        let avgConfidence = selected.map(\.confidence).reduce(0, +) / Double(selected.count)
        if avgConfidence < configuration.lowConfidenceWarningThreshold {
            warnings.append("Average ball tracking confidence is low.")
        }

        return ExperimentalBallLaunchMetrics(
            ballSpeedMph: ballSpeedMph,
            hlaDegrees: imageHLA.hla,
            hlaDisplay: hlaDisplay,
            hla3DRawDegrees: hla3D,
            vlaDegrees: vla,
            hlaReferenceAngleDegrees: zeroDegreeAngleDegrees,
            ballMovementDx: imageHLA.dx,
            ballMovementDy: imageHLA.dy,
            hlaForwardComponent: imageHLA.forward,
            hlaLateralComponent: imageHLA.lateral,
            pointsUsed: selected.count,
            quality: min(1.0, Double(selected.count) / Double(configuration.preferredBallPointLimit)) * avgConfidence,
            method: method,
            warnings: warnings
        )
    }

    // MARK: - Image-space HLA

    private struct ImageSpaceHLAResult {
        let hla: Double?
        let dx: Double?
        let dy: Double?
        let forward: Double?
        let lateral: Double?
        let warnings: [String]
    }

    /// Computes HLA relative to the user-defined 0° reference direction in image space.
    ///
    /// Velocities are scaled to pixel space before projection so the computed angle
    /// matches the visual angle between the drawn 0° ref line and the drawn ball path.
    private func computeImageSpaceHLA(
        observations: [ExperimentalBall3DObservation],
        zeroDegreeAngleDegrees: Double,
        calibration: ExperimentalCameraCalibration
    ) -> ImageSpaceHLAResult {
        var warnings: [String] = []
        guard observations.count >= 2 else {
            return ImageSpaceHLAResult(hla: nil, dx: nil, dy: nil, forward: nil, lateral: nil,
                                       warnings: ["Not enough points for image-space HLA."])
        }

        let times = observations.map { $0.relativeTime }
        let xs    = observations.map { Double($0.imageX) }
        let ys    = observations.map { Double($0.imageY) }

        let meanT = times.reduce(0.0, +) / Double(times.count)
        let denom = times.map { ($0 - meanT) * ($0 - meanT) }.reduce(0.0, +)

        guard denom > 0 else {
            return ImageSpaceHLAResult(hla: nil, dx: nil, dy: nil, forward: nil, lateral: nil,
                                       warnings: ["Invalid time span for image-space HLA."])
        }

        let dxdt = zip(times, xs).map { ($0 - meanT) * $1 }.reduce(0.0, +) / denom
        let dydt = zip(times, ys).map { ($0 - meanT) * $1 }.reduce(0.0, +) / denom

        // Scale to pixel space: the 0° ref line is drawn in pixels, so both vectors
        // must be in the same space for the angle to match the display.
        let W = Double(calibration.imageWidthPixels)
        let H = Double(calibration.imageHeightPixels)
        let dxPx = dxdt * W
        let dyPx = dydt * H

        let movLen = sqrt(dxPx * dxPx + dyPx * dyPx)
        if movLen < 1e-6 {
            warnings.append("Ball 2D movement vector is near zero; HLA unreliable.")
            return ImageSpaceHLAResult(hla: nil, dx: dxdt, dy: dydt, forward: nil, lateral: nil,
                                       warnings: warnings)
        }

        let theta = zeroDegreeAngleDegrees * .pi / 180.0
        let refX  =  cos(theta)
        let refY  = -sin(theta)
        let perpX =  sin(theta)
        let perpY =  cos(theta)

        let forward = dxPx * refX + dyPx * refY
        let lateral = dxPx * perpX + dyPx * perpY

        if abs(forward) < 0.001 * movLen {
            warnings.append("Ball moving nearly perpendicular to 0° reference; HLA near ±90°.")
        }

        let hla = atan2(lateral, forward) * 180.0 / .pi
        return ImageSpaceHLAResult(hla: hla, dx: dxdt, dy: dydt,
                                   forward: forward, lateral: lateral, warnings: warnings)
    }

    // MARK: - Club metrics

    private func calculateClubMetrics(
        clubObservations: [ExperimentalClubObservation],
        ball3DObservations: [ExperimentalBall3DObservation],
        calibration: ExperimentalCameraCalibration,
        impactFrameIndex: Int
    ) -> ExperimentalClubMetrics {
        var warnings = ["Club speed is approximate because club depth is assumed from ball depth near impact."]
        guard let assumedDepth = nearestBallDepth(ball3DObservations, impactFrameIndex: impactFrameIndex) else {
            warnings.append("No ball depth near impact for club speed.")
            return ExperimentalClubMetrics(
                clubSpeedMph: nil, pointsUsed: 0, quality: 0,
                method: "not_enough_data", warnings: warnings, speedFrameIndices: []
            )
        }

        let points = clubObservations
            .filter { $0.frameIndex <= impactFrameIndex && $0.confidence > 0 }
            .compactMap { obs -> (frameIndex: Int, time: Double, position: SIMD3<Double>, confidence: Double)? in
                guard let x = obs.leadingEdgeX ?? obs.centerX,
                      let y = obs.leadingEdgeY ?? obs.centerY,
                      let position = calibration.positionMeters(centerX: x, centerY: y, depthMeters: assumedDepth) else {
                    return nil
                }
                return (obs.frameIndex, obs.relativeTime, position, obs.confidence)
            }
            .sorted { $0.frameIndex < $1.frameIndex }

        guard points.count >= configuration.minimumClubPoints else {
            warnings.append("Not enough club points for club speed.")
            return ExperimentalClubMetrics(
                clubSpeedMph: nil, pointsUsed: points.count, quality: 0,
                method: "not_enough_data", warnings: warnings,
                speedFrameIndices: points.map(\.frameIndex)
            )
        }

        let velocity: SIMD3<Double>?
        let method: String
        if points.count >= 3 {
            velocity = linearFitVelocity(points.map { ($0.time, $0.position) })
            method = "linear_fit_\(points.count)_points_assumed_ball_depth"
        } else {
            let dt = points[1].time - points[0].time
            velocity = dt > 0 ? (points[1].position - points[0].position) / dt : nil
            method = "two_point_delta_assumed_ball_depth"
            warnings.append("Club velocity used 2-point fallback.")
        }

        guard let velocity else {
            warnings.append("Club velocity calculation failed due to invalid time span.")
            return ExperimentalClubMetrics(
                clubSpeedMph: nil, pointsUsed: points.count, quality: 0,
                method: method, warnings: warnings, speedFrameIndices: points.map(\.frameIndex)
            )
        }

        let avgConfidence = points.map(\.confidence).reduce(0, +) / Double(points.count)
        let speedMph = vectorLength(velocity) * 2.23694
        print("Club speed points used: \(points.count)")
        print(String(format: "Club speed: %.1f mph", speedMph))

        return ExperimentalClubMetrics(
            clubSpeedMph: speedMph,
            pointsUsed: points.count,
            quality: min(1.0, Double(points.count) / 6.0) * avgConfidence * 0.65,
            method: method,
            warnings: warnings,
            speedFrameIndices: points.map(\.frameIndex)
        )
    }

    // MARK: - Helpers

    private func nearestBallDepth(_ observations: [ExperimentalBall3DObservation], impactFrameIndex: Int) -> Double? {
        observations
            .filter { $0.frameIndex >= impactFrameIndex - 1 }
            .min { abs($0.frameIndex - impactFrameIndex) < abs($1.frameIndex - impactFrameIndex) }?
            .positionMeters.z
    }

    private func linearFitVelocity(_ points: [(time: Double, position: SIMD3<Double>)]) -> SIMD3<Double>? {
        guard points.count >= 2 else { return nil }
        let meanT = points.map(\.time).reduce(0, +) / Double(points.count)
        let denominator = points.map { pow($0.time - meanT, 2) }.reduce(0, +)
        guard denominator > 0 else { return nil }

        func slope(_ component: KeyPath<SIMD3<Double>, Double>) -> Double {
            points.map { ($0.time - meanT) * $0.position[keyPath: component] }.reduce(0, +) / denominator
        }
        return SIMD3<Double>(slope(\.x), slope(\.y), slope(\.z))
    }

    private func vectorLength(_ vector: SIMD3<Double>) -> Double {
        sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
    }

    private func printSummary(_ result: ExperimentalShotMetricsResult) {
        print("Experimental metrics complete")
        print(result.ballLaunch.ballSpeedMph.map { String(format: "Ball speed: %.1f mph", $0) } ?? "Ball speed: not enough data")
        print(result.ballLaunch.hlaDegrees.map { String(format: "HLA (image-ref): %.1f° (%@)", $0, result.ballLaunch.hlaDisplay) } ?? "HLA: not enough data")
        print(result.ballLaunch.hla3DRawDegrees.map { String(format: "HLA (3D raw): %.1f°", $0) } ?? "HLA 3D: not enough data")
        print(result.ballLaunch.vlaDegrees.map { String(format: "VLA: %.1f°", $0) } ?? "VLA: not enough data")
        print(result.club.clubSpeedMph.map { String(format: "Club speed: %.1f mph", $0) } ?? "Club speed: not enough data")
        print(result.smashFactor.map { String(format: "Smash factor: %.2f", $0) } ?? "Smash factor: not enough data")
        print(result.distance.carryYards.map { String(format: "Estimated carry: %.0f yd (ideal: %.0f yd × cf=%.2f)", $0, result.distance.idealCarryYards ?? 0, result.distance.carryCorrectionFactor) } ?? "Estimated carry: not enough data")
        print(result.distance.totalYards.map { String(format: "Estimated total: %.0f yd (rollout %.0f%%)", $0, (result.distance.rolloutFraction ?? 0) * 100) } ?? "Estimated total: not enough data")
        print(result.spin.estimatedBackspinRpm.map { String(format: "Est. backspin: %.0f rpm", $0) } ?? "Backspin: not enough data")
        print("Club path: \(result.clubPath.clubPathDisplay)  Face: \(result.faceAngle.faceAngleDisplay)  F-to-P: \(result.faceAngle.faceToPathDisplay)")
        print("Experimental metric warnings: \(result.warnings.joined(separator: " | "))")
    }
}
#endif
