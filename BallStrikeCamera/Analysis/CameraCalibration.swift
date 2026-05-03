import Foundation
import CoreGraphics
import simd

struct CameraCalibration {
    var horizontalFOVDegrees: Double
    var verticalFOVDegrees: Double
    var imageWidthPixels: Double
    var imageHeightPixels: Double
    var realBallDiameterMeters: Double
    var cameraHeightMeters: Double?
    var cameraTiltDegrees: Double?

    init(
        horizontalFOVDegrees: Double = 70,
        verticalFOVDegrees: Double = 45,
        imageWidthPixels: Double,
        imageHeightPixels: Double,
        realBallDiameterMeters: Double = 0.04267,
        cameraHeightMeters: Double? = nil,
        cameraTiltDegrees: Double? = nil
    ) {
        self.horizontalFOVDegrees = horizontalFOVDegrees
        self.verticalFOVDegrees = verticalFOVDegrees
        self.imageWidthPixels = imageWidthPixels
        self.imageHeightPixels = imageHeightPixels
        self.realBallDiameterMeters = realBallDiameterMeters
        self.cameraHeightMeters = cameraHeightMeters
        self.cameraTiltDegrees = cameraTiltDegrees
    }

    var focalLengthPixelsX: Double {
        imageWidthPixels / (2 * tan(degreesToRadians(horizontalFOVDegrees) / 2))
    }

    var focalLengthPixelsY: Double {
        imageHeightPixels / (2 * tan(degreesToRadians(verticalFOVDegrees) / 2))
    }

    var averageFocalLengthPixels: Double {
        (focalLengthPixelsX + focalLengthPixelsY) / 2
    }

    var calibrationWarning: String {
        "Camera FOV calibration is using estimated defaults; tune horizontalFOVDegrees and verticalFOVDegrees for trusted metrics."
    }

    static func defaultForImage(width: Int, height: Int) -> CameraCalibration {
        CameraCalibration(
            horizontalFOVDegrees: 70,
            verticalFOVDegrees: 45,
            imageWidthPixels: Double(width),
            imageHeightPixels: Double(height)
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
        let centerPixelX = imageWidthPixels / 2
        let centerPixelY = imageHeightPixels / 2

        let x = (pixelX - centerPixelX) * z / focalLengthPixelsX
        let y = -(pixelY - centerPixelY) * z / focalLengthPixelsY
        return SIMD3<Double>(x, y, z)
    }

    func ballObservation3D(from observation: ShotBallObservation) -> Ball3DObservation? {
        guard let imageX = observation.centerX,
              let imageY = observation.centerY,
              let diameterNorm = observation.finalDiameter ?? observation.diameter,
              observation.confidence > 0 else {
            print("3D conversion skipped for frame \(observation.frameIndex): missing center, diameter, or confidence")
            return nil
        }

        let diameterPixels = Double(diameterNorm) * imageWidthPixels
        guard let depth = depthMeters(apparentDiameterPixels: diameterPixels),
              let position = positionMeters(centerX: imageX, centerY: imageY, depthMeters: depth) else {
            print("3D conversion skipped for frame \(observation.frameIndex): invalid apparent diameter")
            return nil
        }

        return Ball3DObservation(
            frameIndex: observation.frameIndex,
            timestamp: observation.timestamp,
            relativeTime: observation.relativeTime,
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

struct Ball3DObservation {
    let frameIndex: Int
    let timestamp: TimeInterval
    let relativeTime: TimeInterval
    let imageX: CGFloat
    let imageY: CGFloat
    let diameterNorm: CGFloat
    let diameterPixels: Double
    let positionMeters: SIMD3<Double>
    let confidence: Double
}
