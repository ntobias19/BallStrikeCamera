import CoreGraphics

struct BallObservation {
    /// Normalized rect in camera-buffer coordinates: x/y/width/height from 0...1.
    let normalizedRect: CGRect
    let confidence: Double

    var center: CGPoint {
        CGPoint(x: normalizedRect.midX, y: normalizedRect.midY)
    }
}
