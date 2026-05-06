import Foundation
import UIKit
import simd

struct BallLaunchMetrics {
    let ballSpeedMph: Double?
    let hlaDegrees: Double?
    let hlaDisplay: String
    let hla3DRawDegrees: Double?
    let vlaDegrees: Double?
    let hlaReferenceAngleDegrees: Double
    let ballMovementDx: Double?
    let ballMovementDy: Double?
    let hlaForwardComponent: Double?
    let hlaLateralComponent: Double?
    let pointsUsed: Int
    let quality: Double
    let method: String
    let warnings: [String]
}

struct ClubMetrics {
    let clubSpeedMph: Double?
    let pointsUsed: Int
    let quality: Double
    let method: String
    let warnings: [String]
    let speedFrameIndices: [Int]
}

struct ShotMetricsResult {
    let detectedImpactFrameIndex: Int
    let fallbackImpactFrameIndex: Int
    let calibration: CameraCalibration
    let zeroDegreeReferenceAngleDegrees: Double
    let ballLaunch: BallLaunchMetrics
    let club: ClubMetrics
    let smashFactor: Double?
    let distance: DistanceEstimate
    let spin: SpinEstimate
    let clubPath: ClubPathEstimate
    let faceAngle: FaceAngleEstimate
    let ball3DObservations: [Ball3DObservation]
    let clubObservations: [ClubObservation]
    let warnings: [String]
}

struct ShotMetricsCalculator {
    struct Configuration {
        var minimumBallPoints: Int = 2
        var preferredBallPointLimit: Int = 6
        var minimumClubPoints: Int = 2
        var lowConfidenceWarningThreshold: Double = 0.45
    }

    let configuration: Configuration
    let clubTracker: ClubTracker
    let distanceEstimator: DistanceEstimator
    let spinEstimator: SpinEstimator
    let clubPathFaceEstimator: ClubPathFaceEstimator

    init(
        configuration: Configuration = Configuration(),
        clubTracker: ClubTracker = ClubTracker(),
        distanceEstimator: DistanceEstimator = DistanceEstimator(),
        spinEstimator: SpinEstimator = SpinEstimator(),
        clubPathFaceEstimator: ClubPathFaceEstimator = ClubPathFaceEstimator()
    ) {
        self.configuration = configuration
        self.clubTracker = clubTracker
        self.distanceEstimator = distanceEstimator
        self.spinEstimator = spinEstimator
        self.clubPathFaceEstimator = clubPathFaceEstimator
    }

    func calculate(
        for analysis: ShotAnalysisResult,
        zeroDegreeReferenceAngleDegrees: Double = 0.0,
        carryCorrectionFactor: Double = 0.75
    ) -> ShotMetricsResult? {
        print("Shot metrics calculation started")

        guard let calibration = makeCalibration(from: analysis) else {
            print("Shot metrics skipped: no frame image dimensions")
            return nil
        }

        print(String(format: "Camera calibration: fx=%.1f, fy=%.1f, fovX=%.1f, fovY=%.1f",
                     calibration.focalLengthPixelsX,
                     calibration.focalLengthPixelsY,
                     calibration.horizontalFOVDegrees,
                     calibration.verticalFOVDegrees))
        print(calibration.calibrationWarning)

        let ball3DObservations = makeBall3DObservations(from: analysis, calibration: calibration)
        print("3D ball observations: \(ball3DObservations.count)")

        let ballLaunch = calculateBallLaunch(
            ball3DObservations: ball3DObservations,
            impactFrameIndex: analysis.detectedImpactFrameIndex,
            zeroDegreeAngleDegrees: zeroDegreeReferenceAngleDegrees,
            calibration: calibration
        )

        let clubObservations = clubTracker.track(analysis: analysis)
        let clubMetrics = calculateClubMetrics(
            clubObservations: clubObservations,
            ball3DObservations: ball3DObservations,
            calibration: calibration,
            impactFrameIndex: analysis.detectedImpactFrameIndex
        )

        let smashFactor: Double?
        if let ballSpeed = ballLaunch.ballSpeedMph,
           let clubSpeed = clubMetrics.clubSpeedMph,
           clubSpeed > 0 {
            smashFactor = ballSpeed / clubSpeed
        } else {
            smashFactor = nil
        }

        let clubPath = clubPathFaceEstimator.estimateClubPath(
            clubObservations: clubObservations,
            zeroDegreeAngleDegrees: zeroDegreeReferenceAngleDegrees,
            calibration: calibration,
            impactFrameIndex: analysis.detectedImpactFrameIndex
        )

        let impactFrame = analysis.frames
            .first { $0.frameIndex == analysis.detectedImpactFrameIndex }?
            .originalFrame.image
        let faceAngle = clubPathFaceEstimator.estimateFaceAngle(
            clubObservations: clubObservations,
            impactFrame: impactFrame,
            zeroDegreeAngleDegrees: zeroDegreeReferenceAngleDegrees,
            calibration: calibration,
            impactFrameIndex: analysis.detectedImpactFrameIndex,
            clubPathDegrees: clubPath.clubPathDegreesSigned
        )

        let spin = spinEstimator.estimate(
            ballSpeedMph: ballLaunch.ballSpeedMph,
            vlaDegrees: ballLaunch.vlaDegrees,
            hlaDegrees: ballLaunch.hlaDegrees,
            clubPathDegrees: clubPath.clubPathDegreesSigned
        )

        let distance = distanceEstimator.estimate(
            ballSpeedMph: ballLaunch.ballSpeedMph,
            vlaDegrees: ballLaunch.vlaDegrees,
            hlaDegrees: ballLaunch.hlaDegrees,
            carryCorrectionFactor: carryCorrectionFactor
        )

        var warnings: [String] = [calibration.calibrationWarning]
        warnings.append(contentsOf: ballLaunch.warnings)
        warnings.append(contentsOf: clubMetrics.warnings)
        warnings.append(contentsOf: distance.warnings)
        warnings.append(contentsOf: spin.warnings)
        warnings.append(contentsOf: clubPath.warnings)
        warnings.append(contentsOf: faceAngle.warnings)
        if smashFactor == nil {
            warnings.append("Smash factor unavailable until both ball speed and club speed are available.")
        }

        let result = ShotMetricsResult(
            detectedImpactFrameIndex: analysis.detectedImpactFrameIndex,
            fallbackImpactFrameIndex: analysis.fallbackImpactFrameIndex,
            calibration: calibration,
            zeroDegreeReferenceAngleDegrees: zeroDegreeReferenceAngleDegrees,
            ballLaunch: ballLaunch,
            club: clubMetrics,
            smashFactor: smashFactor,
            distance: distance,
            spin: spin,
            clubPath: clubPath,
            faceAngle: faceAngle,
            ball3DObservations: ball3DObservations,
            clubObservations: clubObservations,
            warnings: Array(Set(warnings)).sorted()
        )

        printMetricsSummary(result)
        return result
    }

    private func makeCalibration(from analysis: ShotAnalysisResult) -> CameraCalibration? {
        guard let firstImage = analysis.frames.first?.originalFrame.image.cgImage else { return nil }
        return CameraCalibration.defaultForImage(width: firstImage.width, height: firstImage.height)
    }

    private func makeBall3DObservations(
        from analysis: ShotAnalysisResult,
        calibration: CameraCalibration
    ) -> [Ball3DObservation] {
        analysis.frames.compactMap { frame in
            guard let observation = frame.ballObservation else { return nil }
            return calibration.ballObservation3D(from: observation)
        }
    }

    // MARK: - Ball launch

    private func calculateBallLaunch(
        ball3DObservations: [Ball3DObservation],
        impactFrameIndex: Int,
        zeroDegreeAngleDegrees: Double,
        calibration: CameraCalibration
    ) -> BallLaunchMetrics {
        var warnings: [String] = []
        let postImpact = ball3DObservations
            .filter { $0.frameIndex > impactFrameIndex }
            .sorted { $0.frameIndex < $1.frameIndex }
        let selected = Array(postImpact.prefix(configuration.preferredBallPointLimit))

        guard selected.count >= configuration.minimumBallPoints else {
            warnings.append("Too few post-impact ball points for ball speed/HLA/VLA.")
            return BallLaunchMetrics(
                ballSpeedMph: nil, hlaDegrees: nil, hlaDisplay: "—",
                hla3DRawDegrees: nil, vlaDegrees: nil,
                hlaReferenceAngleDegrees: zeroDegreeAngleDegrees,
                ballMovementDx: nil, ballMovementDy: nil,
                hlaForwardComponent: nil, hlaLateralComponent: nil,
                pointsUsed: selected.count, quality: 0,
                method: "unavailable", warnings: warnings
            )
        }

        let velocity: SIMD3<Double>?
        let method: String
        if selected.count >= 3 {
            velocity = linearFitVelocity(selected.map { ($0.relativeTime, $0.positionMeters) })
            method = "linear_fit_\(selected.count)_points"
        } else {
            velocity = deltaVelocity(first: selected[0], last: selected[1])
            method = "two_point_delta"
            warnings.append("Ball velocity used 2-point fallback.")
        }

        guard let velocity else {
            warnings.append("Ball velocity fit failed because time span was too small.")
            return BallLaunchMetrics(
                ballSpeedMph: nil, hlaDegrees: nil, hlaDisplay: "—",
                hla3DRawDegrees: nil, vlaDegrees: nil,
                hlaReferenceAngleDegrees: zeroDegreeAngleDegrees,
                ballMovementDx: nil, ballMovementDy: nil,
                hlaForwardComponent: nil, hlaLateralComponent: nil,
                pointsUsed: selected.count, quality: 0,
                method: method, warnings: warnings
            )
        }

        let speedMetersPerSecond = vectorLength(velocity)
        let ballSpeedMph = speedMetersPerSecond * 2.23694
        let hla3D = atan2(velocity.x, velocity.z) * 180 / .pi
        let horizontalSpeed = sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
        let vlaDegrees = atan2(velocity.y, horizontalSpeed) * 180 / .pi

        let imageHLA = computeImageSpaceHLA(
            observations: selected,
            zeroDegreeAngleDegrees: zeroDegreeAngleDegrees,
            calibration: calibration
        )
        warnings.append(contentsOf: imageHLA.warnings)

        let hlaDisplay = imageHLA.hla.map { DirectionalFormat.angleLR($0) } ?? "—"

        let avgConfidence = selected.map(\.confidence).reduce(0, +) / Double(selected.count)
        if avgConfidence < configuration.lowConfidenceWarningThreshold {
            warnings.append("Average post-impact ball tracking confidence is low.")
        }
        if selected.count < 3 {
            warnings.append("Ball launch is less stable with fewer than 3 post-impact points.")
        }

        let quality = min(1.0, Double(selected.count) / Double(configuration.preferredBallPointLimit)) * avgConfidence
        return BallLaunchMetrics(
            ballSpeedMph: ballSpeedMph,
            hlaDegrees: imageHLA.hla,
            hlaDisplay: hlaDisplay,
            hla3DRawDegrees: hla3D,
            vlaDegrees: vlaDegrees,
            hlaReferenceAngleDegrees: zeroDegreeAngleDegrees,
            ballMovementDx: imageHLA.dx,
            ballMovementDy: imageHLA.dy,
            hlaForwardComponent: imageHLA.forward,
            hlaLateralComponent: imageHLA.lateral,
            pointsUsed: selected.count,
            quality: quality,
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

    private func computeImageSpaceHLA(
        observations: [Ball3DObservation],
        zeroDegreeAngleDegrees: Double,
        calibration: CameraCalibration
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
        clubObservations: [ClubObservation],
        ball3DObservations: [Ball3DObservation],
        calibration: CameraCalibration,
        impactFrameIndex: Int
    ) -> ClubMetrics {
        var warnings = ["Club speed is approximate because club depth is assumed from ball depth near impact."]

        guard let assumedDepth = nearestBallDepth(ball3DObservations, impactFrameIndex: impactFrameIndex) else {
            warnings.append("Club speed skipped: no ball depth near impact.")
            return ClubMetrics(clubSpeedMph: nil, pointsUsed: 0, quality: 0,
                               method: "unavailable", warnings: warnings, speedFrameIndices: [])
        }

        let points = clubObservations
            .filter { $0.frameIndex <= impactFrameIndex && $0.confidence > 0 }
            .compactMap { observation -> (frameIndex: Int, time: Double, position: SIMD3<Double>, confidence: Double)? in
                guard let x = observation.leadingEdgeX ?? observation.centerX,
                      let y = observation.leadingEdgeY ?? observation.centerY,
                      let position = calibration.positionMeters(centerX: x, centerY: y, depthMeters: assumedDepth) else {
                    return nil
                }
                return (observation.frameIndex, observation.relativeTime, position, observation.confidence)
            }
            .sorted { $0.frameIndex < $1.frameIndex }

        guard points.count >= configuration.minimumClubPoints else {
            warnings.append("Too few club points for club speed.")
            return ClubMetrics(clubSpeedMph: nil, pointsUsed: points.count, quality: 0,
                               method: "unavailable", warnings: warnings,
                               speedFrameIndices: points.map(\.frameIndex))
        }

        let velocity: SIMD3<Double>?
        let method: String
        if points.count >= 3 {
            velocity = linearFitVelocity(points.map { ($0.time, $0.position) })
            method = "linear_fit_\(points.count)_points_assumed_ball_depth"
        } else {
            let first = points[0]
            let last = points[1]
            let dt = last.time - first.time
            velocity = dt > 0 ? (last.position - first.position) / dt : nil
            method = "two_point_delta_assumed_ball_depth"
            warnings.append("Club velocity used 2-point fallback.")
        }

        guard let velocity else {
            warnings.append("Club velocity fit failed because time span was too small.")
            return ClubMetrics(clubSpeedMph: nil, pointsUsed: points.count, quality: 0,
                               method: method, warnings: warnings,
                               speedFrameIndices: points.map(\.frameIndex))
        }

        let avgConfidence = points.map(\.confidence).reduce(0, +) / Double(points.count)
        let clubSpeedMph = vectorLength(velocity) * 2.23694
        let quality = min(1.0, Double(points.count) / 6.0) * avgConfidence * 0.65

        return ClubMetrics(
            clubSpeedMph: clubSpeedMph,
            pointsUsed: points.count,
            quality: quality,
            method: method,
            warnings: warnings,
            speedFrameIndices: points.map(\.frameIndex)
        )
    }

    // MARK: - Helpers

    private func nearestBallDepth(_ observations: [Ball3DObservation], impactFrameIndex: Int) -> Double? {
        observations
            .filter { $0.frameIndex >= impactFrameIndex - 1 }
            .min { abs($0.frameIndex - impactFrameIndex) < abs($1.frameIndex - impactFrameIndex) }?
            .positionMeters.z
    }

    private func deltaVelocity(first: Ball3DObservation, last: Ball3DObservation) -> SIMD3<Double>? {
        let dt = last.relativeTime - first.relativeTime
        guard dt > 0 else { return nil }
        return (last.positionMeters - first.positionMeters) / dt
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

    private func printMetricsSummary(_ result: ShotMetricsResult) {
        print(result.ballLaunch.ballSpeedMph.map { String(format: "Ball speed: %.1f mph", $0) } ?? "Ball speed: unavailable")
        print(result.ballLaunch.hlaDegrees.map { _ in "HLA: \(result.ballLaunch.hlaDisplay)" } ?? "HLA: unavailable")
        print(result.ballLaunch.hla3DRawDegrees.map { String(format: "HLA (3D raw): %.1f°", $0) } ?? "HLA 3D: unavailable")
        print(result.ballLaunch.vlaDegrees.map { String(format: "VLA: %.1f°", $0) } ?? "VLA: unavailable")
        print(result.club.clubSpeedMph.map { String(format: "Club speed: %.1f mph", $0) } ?? "Club speed: unavailable")
        print(result.smashFactor.map { String(format: "Smash factor: %.2f", $0) } ?? "Smash factor: unavailable")
        print(result.distance.carryYards.map { String(format: "Est. carry: %.0f yd (ideal: %.0f yd × cf=%.2f)", $0, result.distance.idealCarryYards ?? 0, result.distance.carryCorrectionFactor) } ?? "Est. carry: unavailable")
        print(result.distance.totalYards.map { String(format: "Est. total: %.0f yd (rollout %.0f%%)", $0, (result.distance.rolloutFraction ?? 0) * 100) } ?? "Est. total: unavailable")
        print(result.spin.estimatedBackspinRpm.map { String(format: "Est. backspin: %.0f rpm", $0) } ?? "Backspin: unavailable")
        print("Club path: \(result.clubPath.clubPathDisplay)  Face: \(result.faceAngle.faceAngleDisplay)  F-to-P: \(result.faceAngle.faceToPathDisplay)")
        if !result.warnings.isEmpty {
            print("Metrics warnings: \(result.warnings.joined(separator: " | "))")
        }
    }
}
