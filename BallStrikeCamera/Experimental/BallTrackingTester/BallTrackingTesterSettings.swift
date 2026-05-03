#if DEBUG
import CoreGraphics

// MARK: - Impact Detection Settings

struct ImpactDetectionSettings {
    var movementThresholdNorm: Double = 0.006
    var confirmFrames:         Double = 2
    var stableWindowCount:     Double = 10

    func toConfig() -> ImpactDetectionConfig {
        ImpactDetectionConfig(
            movementThresholdNorm: CGFloat(movementThresholdNorm),
            confirmFrames:         Int(confirmFrames.rounded()),
            stableWindowCount:     Int(stableWindowCount.rounded())
        )
    }
}

// MARK: - Diameter / Mask Refinement Settings

struct DiameterRefinementSettings {
    var enabled:              Bool   = true
    var localMaskWindowScale: Double = 1.8
    var maskBrightness:       Double = 30
    var maskMaxSpread:        Double = 65
    var minDiameterNorm:      Double = 0.004
    var maxDiameterNorm:      Double = 0.120
    var combineModeIsMax:     Bool   = false   // false = average, true = max
    var smoothingEnabled:     Bool   = true
    var smoothingWindowSize:  Double = 5

    func toConfig() -> ExperimentalBallTracker.DiameterRefinementConfig {
        ExperimentalBallTracker.DiameterRefinementConfig(
            enabled:              enabled,
            localMaskWindowScale: CGFloat(localMaskWindowScale),
            maskBrightness:       Int(maskBrightness.rounded()),
            maskMaxSpread:        Int(maskMaxSpread.rounded()),
            minDiameterNorm:      CGFloat(minDiameterNorm),
            maxDiameterNorm:      CGFloat(maxDiameterNorm),
            combineMode:          combineModeIsMax ? .max : .average,
            smoothingEnabled:     smoothingEnabled,
            smoothingWindowSize:  Int(smoothingWindowSize.rounded())
        )
    }
}

// MARK: - Experimental Calibration Settings

struct CalibrationTuningSettings {
    var horizontalFOVDegrees: Double = 70
    var verticalFOVDegrees:   Double = 45
    var realBallDiameterMeters: Double = 0.04267
    var useCameraHeight: Bool = false
    var cameraHeightMeters: Double = 1.0
    var useCameraTilt: Bool = false
    var cameraTiltDegrees: Double = 0

    mutating func resetDefaults() {
        self = CalibrationTuningSettings()
    }
}

// MARK: - Experimental Club Tracking Settings

struct ClubTrackingTuningSettings {
    var enabled: Bool = true
    var searchBehindBallEnabled: Bool = true
    var ballExclusionRadiusScale: Double = 1.8
    var clubSearchROIScaleX: Double = 6.0
    var clubSearchROIScaleY: Double = 4.0
    var useFrameDifference: Bool = true
    var frameDifferenceThreshold: Double = 34
    var minClubBlobArea: Double = 5
    var maxClubBlobArea: Double = 6000
    var minClubConfidence: Double = 0.20
    var minClubDarknessOrEdgeThreshold: Double = 85
    var debugLoggingEnabled: Bool = true

    var showClubTracker: Bool = true
    var showClubSearchROI: Bool = true
    var showClubPath: Bool = true
    var showBallExclusionZone: Bool = true

    mutating func resetDefaults() {
        self = ClubTrackingTuningSettings()
    }

    func toConfig(trackingMode: FrameNormalizationMode, sampleStride: Double) -> ExperimentalClubTracker.Configuration {
        ExperimentalClubTracker.Configuration(
            enabled: enabled,
            searchBehindBallEnabled: searchBehindBallEnabled,
            ballExclusionRadiusScale: CGFloat(ballExclusionRadiusScale),
            clubSearchROIScaleX: CGFloat(clubSearchROIScaleX),
            clubSearchROIScaleY: CGFloat(clubSearchROIScaleY),
            minClubDarknessOrEdgeThreshold: Int(minClubDarknessOrEdgeThreshold.rounded()),
            useFrameDifference: useFrameDifference,
            frameDifferenceThreshold: Int(frameDifferenceThreshold.rounded()),
            minClubBlobArea: Int(minClubBlobArea.rounded()),
            maxClubBlobArea: Int(maxClubBlobArea.rounded()),
            minClubConfidence: minClubConfidence,
            sampleStride: Int(sampleStride.rounded()),
            debugLoggingEnabled: debugLoggingEnabled,
            normalizationMode: trackingMode
        )
    }
}

// MARK: - Main Tuning Settings

struct BallTrackingTuningSettings {
    var sampleStride: Double = 2

    // Tuned defaults from experimental session (41/41 tracking)
    var preBrightnessThreshold:  Double = 90
    var preMaxChannelSpread:     Double = 90
    var preMinBrightSamples:     Double = 6
    var preMinNormWidth:         Double = 0.008
    var preMaxNormWidth:         Double = 0.090
    var preMinNormHeight:        Double = 0.012
    var preMaxNormHeight:        Double = 0.130
    var preMinAspect:            Double = 0.30
    var preMaxAspect:            Double = 2.00

    var postBrightnessThreshold: Double = 115
    var postMaxChannelSpread:    Double = 110
    var postMinBrightSamples:    Double = 4
    var postMinNormWidth:        Double = 0.005
    var postMaxNormWidth:        Double = 0.120
    var postMinNormHeight:       Double = 0.005
    var postMaxNormHeight:       Double = 0.150
    var postMinAspect:           Double = 0.12
    var postMaxAspect:           Double = 5.00

    var preImpactSearchScale:    Double = 5.67
    var impactSearchScale:       Double = 8.66
    var postImpactBaseScale:     Double = 5.03
    var postImpactScaleGrowth:   Double = 5.00
    var postImpactMaxScale:      Double = 30.0

    var trackingMode:              FrameNormalizationMode  = .darkenedHighContrast
    var diameter:                  DiameterRefinementSettings = DiameterRefinementSettings()
    var impact:                    ImpactDetectionSettings    = ImpactDetectionSettings()
    var calibration:               CalibrationTuningSettings  = CalibrationTuningSettings()
    var club:                      ClubTrackingTuningSettings = ClubTrackingTuningSettings()
    var showOriginalCandidateBounds: Bool = false
    var showMaskPreview:             Bool = true
    var showBallPath:                Bool = true
    var show0DegRef:                 Bool = true
    var zeroDegreeAngleDeg:          Double = 0
    var carryCorrectionFactor:       Double = 0.75

    func toConfiguration() -> ExperimentalBallTracker.Configuration {
        ExperimentalBallTracker.Configuration(
            sampleStride:             Int(sampleStride.rounded()),
            preBrightnessThreshold:   Int(preBrightnessThreshold.rounded()),
            preMaxChannelSpread:      Int(preMaxChannelSpread.rounded()),
            preMinBrightSamples:      Int(preMinBrightSamples.rounded()),
            preMinNormWidth:          CGFloat(preMinNormWidth),
            preMaxNormWidth:          CGFloat(preMaxNormWidth),
            preMinNormHeight:         CGFloat(preMinNormHeight),
            preMaxNormHeight:         CGFloat(preMaxNormHeight),
            preMinAspect:             CGFloat(preMinAspect),
            preMaxAspect:             CGFloat(preMaxAspect),
            postBrightnessThreshold:  Int(postBrightnessThreshold.rounded()),
            postMaxChannelSpread:     Int(postMaxChannelSpread.rounded()),
            postMinBrightSamples:     Int(postMinBrightSamples.rounded()),
            postMinNormWidth:         CGFloat(postMinNormWidth),
            postMaxNormWidth:         CGFloat(postMaxNormWidth),
            postMinNormHeight:        CGFloat(postMinNormHeight),
            postMaxNormHeight:        CGFloat(postMaxNormHeight),
            postMinAspect:            CGFloat(postMinAspect),
            postMaxAspect:            CGFloat(postMaxAspect),
            preImpactSearchScale:     CGFloat(preImpactSearchScale),
            impactSearchScale:        CGFloat(impactSearchScale),
            postImpactBaseScale:      CGFloat(postImpactBaseScale),
            postImpactScaleGrowth:    CGFloat(postImpactScaleGrowth),
            postImpactMaxScale:       CGFloat(postImpactMaxScale),
            normalizationMode:        trackingMode,
            diameterRefinement:       diameter.toConfig(),
            impactDetection:          impact.toConfig()
        )
    }
}
#endif
