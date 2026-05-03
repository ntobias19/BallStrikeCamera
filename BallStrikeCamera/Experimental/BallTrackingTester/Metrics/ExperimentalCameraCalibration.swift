#if DEBUG
import Foundation
import CoreGraphics
import simd

struct ExperimentalCameraCalibration {
    var horizontalFOVDegrees: Double
    var verticalFOVDegrees: Double
    var imageWidthPixels: Double
    var imageHeightPixels: Double
    var realBallDiameterMeters: Double
    var cameraHeightMeters: Double?
    var cameraTiltDegrees: Double?

    var focalLengthPixelsX: Double {
        imageWidthPixels / (2 * tan(degreesToRadians(horizontalFOVDegrees) / 2))
    }

    var focalLengthPixelsY: Double {
        imageHeightPixels / (2 * tan(degreesToRadians(verticalFOVDegrees) / 2))
    }

    var averageFocalLengthPixels: Double {
        (focalLengthPixelsX + focalLengthPixelsY) / 2
    }

    static func from(settings: CalibrationTuningSettings, imageWidth: Int, imageHeight: Int) -> ExperimentalCameraCalibration {
        ExperimentalCameraCalibration(
            horizontalFOVDegrees: settings.horizontalFOVDegrees,
            verticalFOVDegrees: settings.verticalFOVDegrees,
            imageWidthPixels: Double(imageWidth),
            imageHeightPixels: Double(imageHeight),
            realBallDiameterMeters: settings.realBallDiameterMeters,
            cameraHeightMeters: settings.useCameraHeight ? settings.cameraHeightMeters : nil,
            cameraTiltDegrees: settings.useCameraTilt ? settings.cameraTiltDegrees : nil
        )
    }

    func depthMeters(apparentDiameterPixels: Double) -> Double? {
        guard apparentDiameterPixels > 0, averageFocalLengthPixels.isFinite else { return nil }
        return realBallDiameterMeters * averageFocalLengthPixels / apparentDiameterPixels
    }

    func positionMeters(centerX: CGFloat, centerY: CGFloat, depthMeters z: Double) -> SIMD3<Double>? {
        guard z > 0, focalLengthPixelsX > 0, focalLengthPixelsY > 0 else { return nil }

        let pixelX = Double(centerX) * imageWidthPixels
        let pixelY = Double(centerY) * imageHeightPixels
        let principalX = imageWidthPixels / 2
        let principalY = imageHeightPixels / 2
        let x = (pixelX - principalX) * z / focalLengthPixelsX
        let y = -(pixelY - principalY) * z / focalLengthPixelsY
        return SIMD3<Double>(x, y, z)
    }

    func ballObservation3D(
        from observation: BallTrackingTestObservation,
        frame: BallTrackingTestFrame
    ) -> ExperimentalBall3DObservation? {
        guard let imageX = observation.centerX,
              let imageY = observation.centerY,
              let diameterNorm = observation.diameter,
              observation.confidence > 0 else {
            print("Experimental 3D conversion skipped for frame \(observation.frameIndex): missing center, diameter, or confidence")
            return nil
        }

        let diameterPixels = Double(diameterNorm) * imageWidthPixels
        guard let depth = depthMeters(apparentDiameterPixels: diameterPixels),
              let position = positionMeters(centerX: imageX, centerY: imageY, depthMeters: depth) else {
            print("Experimental 3D conversion skipped for frame \(observation.frameIndex): invalid apparent diameter")
            return nil
        }

        return ExperimentalBall3DObservation(
            frameIndex: observation.frameIndex,
            timestamp: frame.timestamp,
            relativeTime: frame.relativeTime,
            imageX: imageX,
            imageY: imageY,
            diameterNorm: diameterNorm,
            diameterPixels: diameterPixels,
            positionMeters: position,
            confidence: observation.confidence
        )
    }

    private func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}
#endif
