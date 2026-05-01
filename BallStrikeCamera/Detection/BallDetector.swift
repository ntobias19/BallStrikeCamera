import CoreVideo
import CoreGraphics

/// A tiny CPU-only detector meant as a replaceable first pass.
///
/// Current heuristic: look for a compact, bright, low-saturation blob. This works best for a white ball
/// against darker grass/turf/backgrounds. Replace this with a CoreML/Vision model later if needed.
final class BallDetector {
    struct Configuration {
        var sampleStride: Int = 6
        var minimumBrightPixels: Int = 18
        var brightnessThreshold: Int = 165
        var maxChannelSpread: Int = 72
        var minimumAspectRatio: CGFloat = 0.55
        var maximumAspectRatio: CGFloat = 1.85
        var minimumNormalizedArea: CGFloat = 0.00002
        var maximumNormalizedArea: CGFloat = 0.04
    }

    private let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func detect(in pixelBuffer: CVPixelBuffer, roi: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> BallObservation? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
        let sampleStride = max(1, configuration.sampleStride)

        // Clamp ROI to valid pixel bounds
        let xStart = max(0, Int(roi.minX * CGFloat(width)))
        let xEnd   = min(width,  Int(roi.maxX * CGFloat(width)))
        let yStart = max(0, Int(roi.minY * CGFloat(height)))
        let yEnd   = min(height, Int(roi.maxY * CGFloat(height)))

        var count = 0
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var sumX = 0
        var sumY = 0

        // Scan only within ROI, downsampled. BGRA byte order.
        // normalizedRect output is always relative to the full frame so overlay mapping is unchanged.
        for y in stride(from: yStart, to: yEnd, by: sampleStride) {
            let row = pointer + y * bytesPerRow
            for x in stride(from: xStart, to: xEnd, by: sampleStride) {
                let idx = x * 4
                let b = Int(row[idx])
                let g = Int(row[idx + 1])
                let r = Int(row[idx + 2])
                let maxChannel = max(r, max(g, b))
                let minChannel = min(r, min(g, b))
                let brightness = (r + g + b) / 3
                let spread = maxChannel - minChannel

                // White balls tend to be bright with modest channel spread.
                if brightness >= configuration.brightnessThreshold && spread <= configuration.maxChannelSpread {
                    count += 1
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                    sumX += x
                    sumY += y
                }
            }
        }

        guard count >= configuration.minimumBrightPixels else { return nil }

        let boxWidth = CGFloat(maxX - minX + sampleStride)
        let boxHeight = CGFloat(maxY - minY + sampleStride)
        guard boxWidth > 0, boxHeight > 0 else { return nil }

        let aspect = boxWidth / boxHeight
        let normalizedArea = (boxWidth * boxHeight) / CGFloat(width * height)
        guard aspect >= configuration.minimumAspectRatio,
              aspect <= configuration.maximumAspectRatio,
              normalizedArea >= configuration.minimumNormalizedArea,
              normalizedArea <= configuration.maximumNormalizedArea else {
            return nil
        }

        let centerX = CGFloat(sumX) / CGFloat(count)
        let centerY = CGFloat(sumY) / CGFloat(count)
        let side = max(boxWidth, boxHeight) * 1.35
        let rect = CGRect(
            x: max(0, centerX - side / 2) / CGFloat(width),
            y: max(0, centerY - side / 2) / CGFloat(height),
            width: min(side, CGFloat(width)) / CGFloat(width),
            height: min(side, CGFloat(height)) / CGFloat(height)
        ).standardized

        let confidence = min(1.0, Double(count) / 240.0)
        return BallObservation(normalizedRect: rect, confidence: confidence)
    }
}

