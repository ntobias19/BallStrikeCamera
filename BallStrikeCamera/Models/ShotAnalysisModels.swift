import Foundation
import UIKit

struct ShotBallObservation {
    let frameIndex: Int
    let timestamp: TimeInterval
    let relativeTime: TimeInterval
    // Nil when tracking failed for this frame.
    let centerX: CGFloat?
    let centerY: CGFloat?
    let diameter: CGFloat?
    let confidence: Double
    let wasInterpolated: Bool
}

struct AnalyzedShotFrame {
    let frameIndex: Int
    let timestamp: TimeInterval
    let relativeTime: TimeInterval
    let originalFrame: CapturedFrame
    // Exposure-lifted/contrast-boosted copy for offline tracking. Nil if normalization failed.
    let normalizedImage: UIImage?
    // Nil until ball tracking is implemented.
    let ballObservation: ShotBallObservation?
}

struct ShotAnalysisResult {
    let frames: [AnalyzedShotFrame]
    let impactFrameIndex: Int
    let lockedBallRect: CGRect?
    let createdAt: Date
}
