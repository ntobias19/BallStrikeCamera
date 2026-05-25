import Foundation
import CoreLocation

// MARK: - Shot Context

/// Carries metadata about where a shot originated, enabling downstream views
/// (ShotResultView, ShotTrackingReviewView) to adapt their presentation.
struct ShotContext {
    enum SourceMode {
        case range
        case sim
        case course
    }

    var sourceMode: SourceMode     = .range
    var courseRoundId: UUID?       = nil
    var holeNumber: Int?           = nil
    var holePar: Int?              = nil
    var holeYardage: Int?          = nil
    var courseName: String?        = nil
    var holeHandicap: Int?         = nil

    // Course-mode geography — used by CourseLandingMapView to show where
    // the ball lands on the satellite view in the right animation panel.
    var playerCoordinate: CLLocationCoordinate2D?       = nil
    var greenCenterCoordinate: CLLocationCoordinate2D?  = nil
    var teeCoordinate: CLLocationCoordinate2D?          = nil
    var holePathCoordinates: [CLLocationCoordinate2D]   = []

    var shotMode: ShotMode {
        switch sourceMode {
        case .range:  return .range
        case .sim:    return .sim
        case .course: return .course
        }
    }
}
