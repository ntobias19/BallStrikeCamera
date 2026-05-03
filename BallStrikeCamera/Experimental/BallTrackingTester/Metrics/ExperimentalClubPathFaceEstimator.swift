#if DEBUG
import Foundation
import CoreGraphics
import UIKit

struct ExperimentalClubPathFaceEstimator {

    // MARK: - Club path

    func estimateClubPath(
        clubObservations: [ExperimentalClubObservation],
        zeroDegreeAngleDegrees: Double,
        calibration: ExperimentalCameraCalibration,
        impactFrameIndex: Int
    ) -> ExperimentalClubPathEstimate {
        let preImpact = clubObservations
            .filter { $0.frameIndex <= impactFrameIndex && $0.centerX != nil && $0.centerY != nil }
            .sorted { $0.frameIndex < $1.frameIndex }

        guard preImpact.count >= 2 else {
            return ExperimentalClubPathEstimate(
                clubPathDegreesSigned: nil, clubPathDisplay: "—",
                confidence: 0, method: "not_enough_data",
                warnings: ["Not enough pre-impact club observations for path angle."]
            )
        }

        let times = preImpact.map { $0.relativeTime }
        let xs    = preImpact.compactMap { $0.centerX.map(Double.init) }
        let ys    = preImpact.compactMap { $0.centerY.map(Double.init) }

        guard xs.count == preImpact.count else {
            return ExperimentalClubPathEstimate(
                clubPathDegreesSigned: nil, clubPathDisplay: "—",
                confidence: 0, method: "incomplete_data",
                warnings: ["Some club observations missing center coordinates."]
            )
        }

        let meanT  = times.reduce(0, +) / Double(times.count)
        let denom  = times.map { ($0 - meanT) * ($0 - meanT) }.reduce(0, +)
        guard denom > 1e-12 else {
            return ExperimentalClubPathEstimate(
                clubPathDegreesSigned: nil, clubPathDisplay: "—",
                confidence: 0, method: "zero_time_span",
                warnings: ["Zero time span in club path estimation."]
            )
        }

        let W = Double(calibration.imageWidthPixels)
        let H = Double(calibration.imageHeightPixels)

        let dxdt = zip(times, xs).map { ($0 - meanT) * $1 }.reduce(0, +) / denom
        let dydt = zip(times, ys).map { ($0 - meanT) * $1 }.reduce(0, +) / denom
        let dxPx = dxdt * W
        let dyPx = dydt * H

        let movLen = sqrt(dxPx * dxPx + dyPx * dyPx)
        guard movLen > 1e-6 else {
            return ExperimentalClubPathEstimate(
                clubPathDegreesSigned: nil, clubPathDisplay: "—",
                confidence: 0, method: "near_zero_movement",
                warnings: ["Club 2D movement vector near zero."]
            )
        }

        let theta   = zeroDegreeAngleDegrees * .pi / 180.0
        let refX    =  cos(theta);  let refY  = -sin(theta)
        let perpX   =  sin(theta);  let perpY =  cos(theta)
        let forward = dxPx * refX + dyPx * refY
        let lateral = dxPx * perpX + dyPx * perpY

        let clubPath = atan2(lateral, forward) * 180.0 / .pi
        let display  = ExperimentalDirectionalFormat.angleLR(clubPath)

        return ExperimentalClubPathEstimate(
            clubPathDegreesSigned: clubPath,
            clubPathDisplay: display,
            confidence: min(1.0, Double(preImpact.count) / 5.0),
            method: "image_space_linear_fit_\(preImpact.count)pts",
            warnings: ["Club path is image-space estimate. Accuracy depends on camera calibration."]
        )
    }

    // MARK: - Face angle (gradient PCA on clubhead bbox)

    func estimateFaceAngle(
        clubObservations: [ExperimentalClubObservation],
        impactFrame: UIImage?,
        zeroDegreeAngleDegrees: Double,
        calibration: ExperimentalCameraCalibration,
        impactFrameIndex: Int,
        clubPathDegrees: Double?
    ) -> ExperimentalFaceAngleEstimate {
        let nearImpact = clubObservations
            .filter { $0.clubBoundingBox != nil && $0.frameIndex <= impactFrameIndex }
            .sorted { abs($0.frameIndex - impactFrameIndex) < abs($1.frameIndex - impactFrameIndex) }

        guard let impObs = nearImpact.first, let bbox = impObs.clubBoundingBox else {
            return unavailableFaceAngle(reason: "no_bounding_box",
                                        warning: "Face angle unavailable: no clubhead bounding box near impact.")
        }

        // Try pixel gradient PCA
        if let frame = impactFrame,
           let result = gradientFaceAngle(image: frame, bbox: bbox,
                                          zeroDeg: zeroDegreeAngleDegrees, calibration: calibration) {
            let (faceAngle, pixelConf) = result
            let faceDisplay  = ExperimentalDirectionalFormat.angleLR(faceAngle)
            let ftp          = clubPathDegrees.map { faceAngle - $0 }
            let ftpDisplay   = ftp.map { ExperimentalDirectionalFormat.angleLR($0) } ?? "—"

            return ExperimentalFaceAngleEstimate(
                faceAngleDegreesSigned: faceAngle,
                faceAngleDisplay: faceDisplay,
                faceToPathDegreesSigned: ftp,
                faceToPathDisplay: ftpDisplay,
                confidence: pixelConf < 0.25 ? "low_gradient" : "moderate_gradient",
                method: "bbox_edge_gradient_pca",
                warnings: [
                    "Face angle is ESTIMATED from edge gradients in clubhead bounding box.",
                    "Motion blur at impact typically reduces reliability. Treat as indicative only."
                ]
            )
        }

        // Fallback: bbox aspect ratio heuristic
        let W = Double(calibration.imageWidthPixels)
        let H = Double(calibration.imageHeightPixels)
        let bboxW = bbox.width  * CGFloat(W)
        let bboxH = bbox.height * CGFloat(H)

        // Longer bbox axis approximates shaft direction; face is perpendicular.
        // This is a very rough heuristic — mark as low confidence.
        let shaftAngleRad  = bboxW >= bboxH ? 0.0 : .pi / 2.0
        let faceAngleRad   = shaftAngleRad + .pi / 2.0

        let theta   = zeroDegreeAngleDegrees * .pi / 180.0
        let refX    = cos(theta);  let refY  = -sin(theta)
        let perpX   = sin(theta);  let perpY =  cos(theta)
        let fDirX   = cos(faceAngleRad)
        let fDirY   = sin(faceAngleRad)
        let forward = fDirX * refX + fDirY * refY
        let lateral = fDirX * perpX + fDirY * perpY
        let faceAngle = atan2(lateral, forward) * 180.0 / .pi
        let faceDisplay = ExperimentalDirectionalFormat.angleLR(faceAngle)
        let ftp      = clubPathDegrees.map { faceAngle - $0 }
        let ftpDisplay = ftp.map { ExperimentalDirectionalFormat.angleLR($0) } ?? "—"

        return ExperimentalFaceAngleEstimate(
            faceAngleDegreesSigned: faceAngle,
            faceAngleDisplay: faceDisplay,
            faceToPathDegreesSigned: ftp,
            faceToPathDisplay: ftpDisplay,
            confidence: "low_bbox_heuristic",
            method: "bbox_aspect_ratio_heuristic",
            warnings: [
                "Face angle is a rough heuristic based on bounding box aspect ratio. Very low confidence.",
                "No pixel data was available for gradient analysis."
            ]
        )
    }

    // MARK: - Gradient PCA

    private func gradientFaceAngle(
        image: UIImage,
        bbox: CGRect,
        zeroDeg: Double,
        calibration: ExperimentalCameraCalibration
    ) -> (angle: Double, confidence: Double)? {
        guard let cgImage = image.cgImage else { return nil }
        let W = calibration.imageWidthPixels
        let H = calibration.imageHeightPixels

        let x0 = max(0, Int(bbox.minX  * CGFloat(W)))
        let y0 = max(0, Int(bbox.minY  * CGFloat(H)))
        let rw = max(1, Int(bbox.width  * CGFloat(W)))
        let rh = max(1, Int(bbox.height * CGFloat(H)))
        let x1 = min(W, x0 + rw)
        let y1 = min(H, y0 + rh)
        let cropW = x1 - x0;  let cropH = y1 - y0
        guard cropW >= 3, cropH >= 3 else { return nil }

        guard let cropped = cgImage.cropping(
            to: CGRect(x: x0, y: y0, width: cropW, height: cropH)
        ) else { return nil }

        // Draw into grayscale bitmap
        let stride   = cropW
        var pixels   = [UInt8](repeating: 0, count: stride * cropH)
        guard let ctx = CGContext(
            data: &pixels, width: cropW, height: cropH,
            bitsPerComponent: 8, bytesPerRow: stride,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: cropW, height: cropH))

        // Sobel + circular-statistics accumulation for dominant edge direction
        let idx: (Int, Int) -> Int = { r, c in r * stride + c }
        var cosSum = 0.0, sinSum = 0.0, weightSum = 0.0

        for r in 1..<(cropH - 1) {
            for c in 1..<(cropW - 1) {
                let gx = (Int(pixels[idx(r-1, c+1)]) + 2 * Int(pixels[idx(r, c+1)]) + Int(pixels[idx(r+1, c+1)]))
                       - (Int(pixels[idx(r-1, c-1)]) + 2 * Int(pixels[idx(r, c-1)]) + Int(pixels[idx(r+1, c-1)]))
                let gy = (Int(pixels[idx(r+1, c-1)]) + 2 * Int(pixels[idx(r+1, c)]) + Int(pixels[idx(r+1, c+1)]))
                       - (Int(pixels[idx(r-1, c-1)]) + 2 * Int(pixels[idx(r-1, c)]) + Int(pixels[idx(r-1, c+1)]))
                let mag = sqrt(Double(gx * gx + gy * gy))
                guard mag > 20 else { continue }
                // Edge direction is perpendicular to gradient: θ_edge = atan2(gx, gy)
                let edgeAngle = atan2(Double(gx), Double(gy))
                // Double-angle trick for 180° ambiguity
                cosSum    += cos(2 * edgeAngle) * mag
                sinSum    += sin(2 * edgeAngle) * mag
                weightSum += mag
            }
        }

        guard weightSum > 0 else { return nil }

        let dominantEdgeAngle = atan2(sinSum, cosSum) / 2.0
        let coherence         = sqrt(cosSum * cosSum + sinSum * sinSum) / weightSum

        // Project face direction onto ref/perp axes
        let theta   = zeroDeg * .pi / 180.0
        let refX    = cos(theta);  let refY  = -sin(theta)
        let perpX   = sin(theta);  let perpY =  cos(theta)
        let fDirX   = cos(dominantEdgeAngle)
        let fDirY   = sin(dominantEdgeAngle)
        let forward = fDirX * refX + fDirY * refY
        let lateral = fDirX * perpX + fDirY * perpY

        let faceAngle = atan2(lateral, forward) * 180.0 / .pi
        return (faceAngle, coherence)
    }

    // MARK: - Helper

    private func unavailableFaceAngle(reason: String, warning: String) -> ExperimentalFaceAngleEstimate {
        ExperimentalFaceAngleEstimate(
            faceAngleDegreesSigned: nil, faceAngleDisplay: "—",
            faceToPathDegreesSigned: nil, faceToPathDisplay: "—",
            confidence: "unavailable", method: reason,
            warnings: [warning]
        )
    }
}
#endif
