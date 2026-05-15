import UIKit

enum CompositeStyle: String, CaseIterable {
    case twentyOneFrame  = "21 Frames"
    case elevenFrame     = "11 Frames"
    case postImpactOnly  = "Post-Impact"

    // Short label for the compact top-bar picker.
    var shortName: String {
        switch self {
        case .twentyOneFrame:  return "21F"
        case .elevenFrame:     return "11F"
        case .postImpactOnly:  return "Post"
        }
    }

    // Frame range relative to the impact index.
    func frameRange(impact: Int, totalFrames: Int) -> ClosedRange<Int> {
        switch self {
        case .twentyOneFrame:
            return max(0, impact - 10)...min(totalFrames - 1, impact + 10)
        case .elevenFrame:
            return max(0, impact - 5)...min(totalFrames - 1, impact + 5)
        case .postImpactOnly:
            let start = min(impact + 1, totalFrames - 1)
            let end   = min(totalFrames - 1, impact + 10)
            return start...max(start, end)
        }
    }

    // Per-frame alpha — fewer frames need higher alpha to accumulate enough brightness.
    var frameAlpha: CGFloat {
        switch self {
        case .twentyOneFrame:  return 0.045
        case .elevenFrame:     return 0.080
        case .postImpactOnly:  return 0.100
        }
    }

    // Impact frame rendered brighter for 21F and 11F; postImpactOnly excludes the impact frame.
    var highlightImpactFrame: Bool {
        switch self {
        case .twentyOneFrame, .elevenFrame: return true
        case .postImpactOnly:               return false
        }
    }
}

final class ShotCompositeRenderer {

    struct Configuration {
        var style:               CompositeStyle = .elevenFrame
        // nil = use style default; set explicitly to override.
        var frameAlphaOverride:  CGFloat?       = nil
        var impactFrameAlpha:    CGFloat        = 0.16
    }

    func render(
        analysis: ShotAnalysisResult,
        mode: FrameNormalizationMode,
        configuration: Configuration = Configuration()
    ) -> UIImage? {
        let frames = analysis.frames
        guard !frames.isEmpty else { return nil }

        let impact   = analysis.impactFrameIndex
        let style    = configuration.style
        let range    = style.frameRange(impact: impact, totalFrames: frames.count)
        let selected = Array(frames[range])

        // Use the first selected frame as background reference (pre-impact for 21F/11F).
        guard let bgImg  = sourceImage(selected[0], mode: mode),
              let bgCG   = bgImg.cgImage else { return nil }

        let width  = bgCG.width
        let height = bgCG.height
        let size   = CGSize(width: width, height: height)

        print("Rendering composite at source resolution: \(width) x \(height)")
        print("Composite style: \(style.rawValue)")
        print("Composite frame range: \(range.lowerBound)...\(range.upperBound)")
        print("Composite image mode: \(mode.displayName)")
        let brightThreshold = 16  // lowered from 22 to catch more ball-edge pixels
        let darkThreshold   = 13  // lowered from 18 to catch more club-edge pixels
        let dilationRadius  = 1   // 4-connected pixel dilation to fill outline gaps

        print(String(format: "Composite blend: background_motion_mask_with_dilation brightThresh=%d darkThresh=%d dilationRadius=%d",
                     brightThreshold, darkThreshold, dilationRadius))

        let bytesPerPixel = 4
        let bytesPerRow   = bytesPerPixel * width
        let totalBytes    = bytesPerRow * height
        let pixelCount    = width * height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        // Extract background pixels.
        var bgBytes = [UInt8](repeating: 0, count: totalBytes)
        guard let bgCtx = CGContext(
            data: &bgBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        bgCtx.draw(bgCG, in: CGRect(origin: .zero, size: size))

        // Initialize the composite buffer as a copy of the background.
        var compositeBytes = bgBytes

        var brightMotionPixels = 0
        var darkMotionPixels   = 0

        var fallbackLogged = false
        for frame in selected {
            guard let frameImg = sourceImageWithFallback(frame, mode: mode, fallbackLogged: &fallbackLogged),
                  let frameCG  = frameImg.cgImage else { continue }

            var frameBytes = [UInt8](repeating: 0, count: totalBytes)
            guard let frameCtx = CGContext(
                data: &frameBytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { continue }
            frameCtx.draw(frameCG, in: CGRect(origin: .zero, size: size))

            // Pass 1: build per-frame bright/dark motion masks.
            var brightMask = [Bool](repeating: false, count: pixelCount)
            var darkMask   = [Bool](repeating: false, count: pixelCount)
            for i in 0..<pixelCount {
                let bi       = i * 4
                let frameLum = (Int(frameBytes[bi]) + Int(frameBytes[bi+1]) + Int(frameBytes[bi+2])) / 3
                let bgLum    = (Int(bgBytes[bi])    + Int(bgBytes[bi+1])    + Int(bgBytes[bi+2]))    / 3
                let delta    = frameLum - bgLum
                if delta  > brightThreshold { brightMask[i] = true }
                if delta  < -darkThreshold  { darkMask[i]   = true }
            }

            // Pass 2: dilate both masks by dilationRadius (4-connected, 1 pixel).
            var dilatedBright = brightMask
            var dilatedDark   = darkMask
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * width + x
                    if brightMask[i] {
                        if x > 0          { dilatedBright[i - 1]     = true }
                        if x < width - 1  { dilatedBright[i + 1]     = true }
                        if y > 0          { dilatedBright[i - width]  = true }
                        if y < height - 1 { dilatedBright[i + width]  = true }
                    }
                    if darkMask[i] {
                        if x > 0          { dilatedDark[i - 1]     = true }
                        if x < width - 1  { dilatedDark[i + 1]     = true }
                        if y > 0          { dilatedDark[i - width]  = true }
                        if y < height - 1 { dilatedDark[i + width]  = true }
                    }
                }
            }

            // Pass 3: apply composite using dilated masks — brightest wins for ball, darkest wins for club.
            for i in 0..<pixelCount {
                let bi       = i * 4
                let fR = Int(frameBytes[bi]), fG = Int(frameBytes[bi+1]), fB = Int(frameBytes[bi+2])
                let frameLum = (fR + fG + fB) / 3
                let compLum  = (Int(compositeBytes[bi]) + Int(compositeBytes[bi+1]) + Int(compositeBytes[bi+2])) / 3

                if dilatedBright[i] {
                    if frameLum > compLum {
                        compositeBytes[bi]   = frameBytes[bi];   compositeBytes[bi+1] = frameBytes[bi+1]
                        compositeBytes[bi+2] = frameBytes[bi+2]; compositeBytes[bi+3] = frameBytes[bi+3]
                        brightMotionPixels += 1
                    }
                } else if dilatedDark[i] {
                    if frameLum < compLum {
                        compositeBytes[bi]   = frameBytes[bi];   compositeBytes[bi+1] = frameBytes[bi+1]
                        compositeBytes[bi+2] = frameBytes[bi+2]; compositeBytes[bi+3] = frameBytes[bi+3]
                        darkMotionPixels += 1
                    }
                }
                // else: background region — leave composite unchanged.
            }
        }

        print("Composite mask tuning: brightThreshold=\(brightThreshold) darkThreshold=\(darkThreshold) dilationRadius=\(dilationRadius)")
        print("Composite: brightMotionPixels=\(brightMotionPixels) darkMotionPixels=\(darkMotionPixels) method=background_motion_mask_full_strength_with_dilation")

        // Render composite buffer as UIImage using withUnsafeMutableBytes + CGContext.
        var compositeData = compositeBytes
        guard let outputCtx = compositeData.withUnsafeMutableBytes({ ptr -> CGContext? in
            guard let baseAddress = ptr.baseAddress else { return nil }
            return CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            )
        }),
        let outputCG = outputCtx.makeImage() else { return nil }

        let result = UIImage(cgImage: outputCG, scale: bgImg.scale, orientation: bgImg.imageOrientation)
        print("Shot composite rendered")
        return result
    }

    // MARK: - Private

    private func sourceImage(_ frame: AnalyzedShotFrame, mode: FrameNormalizationMode) -> UIImage? {
        switch mode {
        case .original:            return frame.originalFrame.image
        case .brightened:          return frame.brightenedImage           ?? frame.originalFrame.image
        case .darkenedHighContrast: return frame.darkenedHighContrastImage ?? frame.originalFrame.image
        }
    }

    private func sourceImageWithFallback(
        _ frame: AnalyzedShotFrame,
        mode: FrameNormalizationMode,
        fallbackLogged: inout Bool
    ) -> UIImage? {
        if mode == .darkenedHighContrast, frame.darkenedHighContrastImage == nil {
            if !fallbackLogged {
                print("ShotCompositeRenderer: darkenedHighContrast missing for frame \(frame.frameIndex), using original")
                fallbackLogged = true
            }
            return frame.originalFrame.image
        }
        return sourceImage(frame, mode: mode)
    }
}
