import UIKit
import CoreImage

final class FrameNormalizer {
    struct Configuration {
        var exposureEV: Float = 1.2
        var contrast: Float = 1.25
        var gammaPower: Float = 0.9
        var isDebugLoggingEnabled: Bool = true
    }

    private let configuration: Configuration
    private let context: CIContext

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        // Shared CIContext with no color management for speed.
        self.context = CIContext(options: [.workingColorSpace: NSNull()])
    }

    func normalizedImage(from image: UIImage) -> UIImage {
        guard let cgInput = image.cgImage else { return image }

        var ci = CIImage(cgImage: cgInput)

        // 1. Exposure lift.
        if let filter = CIFilter(name: "CIExposureAdjust") {
            filter.setValue(ci, forKey: kCIInputImageKey)
            filter.setValue(configuration.exposureEV, forKey: kCIInputEVKey)
            if let output = filter.outputImage { ci = output }
        }

        // 2. Contrast boost (brightness kept at 0 — exposure filter handles lift).
        if let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(ci, forKey: kCIInputImageKey)
            filter.setValue(configuration.contrast, forKey: kCIInputContrastKey)
            filter.setValue(0.0, forKey: kCIInputBrightnessKey)
            if let output = filter.outputImage { ci = output }
        }

        // 3. Gamma correction — pulls midtones up when < 1.
        if let filter = CIFilter(name: "CIGammaAdjust") {
            filter.setValue(ci, forKey: kCIInputImageKey)
            filter.setValue(configuration.gammaPower, forKey: "inputPower")
            if let output = filter.outputImage { ci = output }
        }

        guard let cgOutput = context.createCGImage(ci, from: ci.extent) else { return image }
        return UIImage(cgImage: cgOutput, scale: image.scale, orientation: image.imageOrientation)
    }
}
