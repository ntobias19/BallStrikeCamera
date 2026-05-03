import Foundation
import UIKit
import simd

struct BallLaunchMetrics {
    let ballSpeedMph: Double?
    let hlaDegrees: Double?
    let vlaDegrees: Double?
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
}

struct ShotMetricsResult {
    let detectedImpactFrameIndex: Int
    let fallbackImpactFrameIndex: Int
    let calibration: CameraCalibration
    let ballLaunch: BallLaunchMetrics
    let club: ClubMetrics
    let smashFactor: Double?
    let distance: DistanceEstimate
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

    init(
        configuration: Configuration = Configuration(),
        clubTracker: ClubTracker = ClubTracker(),
        distanceEstimator: DistanceEstimator = DistanceEstimator()
    ) {
        self.configuration = configuration
        self.clubTracker = clubTracker
        self.distanceEstimator = distanceEstimator
    }

    func calculate(for analysis: ShotAnalysisResult) -> ShotMetricsResult? {
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
            impactFrameIndex: analysis.detectedImpactFrameIndex
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

        let distance = distanceEstimator.estimate(
            ballSpeedMph: ballLaunch.ballSpeedMph,
            vlaDegrees: ballLaunch.vlaDegrees,
            hlaDegrees: ballLaunch.hlaDegrees
        )

        var warnings: [String] = [calibration.calibrationWarning]
        warnings.append(contentsOf: ballLaunch.warnings)
        warnings.append(contentsOf: clubMetrics.warnings)
        warnings.append(contentsOf: distance.warnings)
        if clubMetrics.quality < configuration.lowConfidenceWarningThreshold {
            warnings.append("Club speed confidence is low; smash factor may be unreliable.")
        }
        if smashFactor == nil {
            warnings.append("Smash factor unavailable until both ball speed and club speed are available.")
        }

        let result = ShotMetricsResult(
            detectedImpactFrameIndex: analysis.detectedImpactFrameIndex,
            fallbackImpactFrameIndex: analysis.fallbackImpactFrameIndex,
            calibration: calibration,
            ballLaunch: ballLaunch,
            club: clubMetrics,
            smashFactor: smashFactor,
            distance: distance,
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

    private func calculateBallLaunch(
        ball3DObservations: [Ball3DObservation],
        impactFrameIndex: Int
    ) -> BallLaunchMetrics {
        var warnings: [String] = []
        let postImpact = ball3DObservations
            .filter { $0.frameIndex > impactFrameIndex }
            .sorted { $0.frameIndex < $1.frameIndex }
        let selected = Array(postImpact.prefix(configuration.preferredBallPointLimit))

        guard selected.count >= configuration.minimumBallPoints else {
            warnings.append("Too few post-impact ball points for ball speed/HLA/VLA.")
            return BallLaunchMetrics(
                ballSpeedMph: nil,
                hlaDegrees: nil,
                vlaDegrees: nil,
                pointsUsed: selected.count,
                quality: 0,
                method: "unavailable",
                warnings: warnings
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
                ballSpeedMph: nil,
                hlaDegrees: nil,
                vlaDegrees: nil,
                pointsUsed: selected.count,
                quality: 0,
                method: method,
                warnings: warnings
            )
        }

        let speedMetersPerSecond = vectorLength(velocity)
        let ballSpeedMph = speedMetersPerSecond * 2.23694
        let hlaDegrees = atan2(velocity.x, velocity.z) * 180 / .pi
        let horizontalSpeed = sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
        let vlaDegrees = atan2(velocity.y, horizontalSpeed) * 180 / .pi
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
            hlaDegrees: hlaDegrees,
            vlaDegrees: vlaDegrees,
            pointsUsed: selected.count,
            quality: quality,
            method: method,
            warnings: warnings
        )
    }

    private func calculateClubMetrics(
        clubObservations: [ClubObservation],
        ball3DObservations: [Ball3DObservation],
        calibration: CameraCalibration,
        impactFrameIndex: Int
    ) -> ClubMetrics {
        var warnings = ["Club speed is approximate because club depth is assumed from ball depth near impact."]

        guard let assumedDepth = nearestBallDepth(ball3DObservations, impactFrameIndex: impactFrameIndex) else {
            warnings.append("Club speed skipped: no ball depth near impact.")
            return ClubMetrics(clubSpeedMph: nil, pointsUsed: 0, quality: 0, method: "unavailable", warnings: warnings)
        }

        let points = clubObservations
            .filter { $0.frameIndex <= impactFrameIndex && $0.confidence > 0 }
            .compactMap { observation -> (time: Double, position: SIMD3<Double>, confidence: Double)? in
                guard let x = observation.leadingEdgeX ?? observation.centerX,
                      let y = observation.leadingEdgeY ?? observation.centerY,
                      let position = calibration.positionMeters(centerX: x, centerY: y, depthMeters: assumedDepth) else {
                    return nil
                }
                return (observation.relativeTime, position, observation.confidence)
            }
            .sorted { $0.time < $1.time }

        guard points.count >= configuration.minimumClubPoints else {
            warnings.append("Too few club points for club speed.")
            return ClubMetrics(clubSpeedMph: nil, pointsUsed: points.count, quality: 0, method: "unavailable", warnings: warnings)
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
            return ClubMetrics(clubSpeedMph: nil, pointsUsed: points.count, quality: 0, method: method, warnings: warnings)
        }

        let avgConfidence = points.map(\.confidence).reduce(0, +) / Double(points.count)
        let clubSpeedMph = vectorLength(velocity) * 2.23694
        let quality = min(1.0, Double(points.count) / 6.0) * avgConfidence * 0.65

        return ClubMetrics(
            clubSpeedMph: clubSpeedMph,
            pointsUsed: points.count,
            quality: quality,
            method: method,
            warnings: warnings
        )
    }

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
        print(result.ballLaunch.hlaDegrees.map { String(format: "HLA: %.1f degrees", $0) } ?? "HLA: unavailable")
        print(result.ballLaunch.vlaDegrees.map { String(format: "VLA: %.1f degrees", $0) } ?? "VLA: unavailable")
        print(result.club.clubSpeedMph.map { String(format: "Club speed: %.1f mph", $0) } ?? "Club speed: unavailable")
        print(result.smashFactor.map { String(format: "Smash factor: %.2f", $0) } ?? "Smash factor: unavailable")
        print(result.distance.carryYards.map { String(format: "Carry estimate: %.0f yd", $0) } ?? "Carry estimate: unavailable")
        print(result.distance.totalYards.map { String(format: "Total estimate: %.0f yd", $0) } ?? "Total estimate: unavailable")
        if result.warnings.isEmpty {
            print("Metrics warnings: none")
        } else {
            print("Metrics warnings: \(result.warnings.joined(separator: " | "))")
        }
    }
}
