import SwiftUI
import MapKit

// MARK: - Overlays / Annotations

private final class HolePathOverlay: MKPolyline {}

/// Coordinate is updated every animation frame to move the ball.
private final class BallInFlightAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(_ c: CLLocationCoordinate2D) { coordinate = c }
}

private final class LandingRingAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(_ c: CLLocationCoordinate2D) { coordinate = c }
}

private final class PinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(_ c: CLLocationCoordinate2D) { coordinate = c }
}

// MARK: - CourseLandingMapView

struct CourseLandingMapView: UIViewRepresentable {

    let context: ShotContext
    let metrics: ShotMetricsResult?
    /// 0→1 carry/flight phase.
    let flightProgress: Double
    /// 0→1 rollout phase (starts after carry).
    let rolloutProgress: Double

    // MARK: Derived geometry

    private var origin: CLLocationCoordinate2D? {
        context.playerCoordinate ?? context.teeCoordinate
    }

    var landingCoordinate: CLLocationCoordinate2D? {
        guard let o = origin,
              let green = context.greenCenterCoordinate,
              let m = metrics else { return nil }
        guard let carryYds = (m.distance.totalYards ?? m.distance.carryYards)
                .flatMap({ $0 > 0 ? $0 : nil }) else { return nil }
        let bearing   = GolfGeometry.bearing(from: o, to: green)
        let signedHLA = m.ballLaunch.hlaDegrees ?? 0
        return GolfGeometry.project(from: o,
                                    bearingDegrees: bearing + signedHLA,
                                    distanceMeters: carryYds / 1.09361)
    }

    private var rolloutEndCoordinate: CLLocationCoordinate2D? {
        guard let o = origin, let l = landingCoordinate, let m = metrics else { return nil }
        let total = m.distance.totalYards ?? 0
        let carry = m.distance.carryYards ?? 0
        let rollYds = max(0, total - carry)
        guard rollYds > 0.5 else { return nil }
        let bearing = GolfGeometry.bearing(from: o, to: l)
        return GolfGeometry.project(from: l, bearingDegrees: bearing,
                                    distanceMeters: rollYds / 1.09361)
    }

    // MARK: UIViewRepresentable

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context ctx: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType           = .hybrid
        map.isScrollEnabled   = false
        map.isZoomEnabled     = false
        map.isRotateEnabled   = false
        map.isPitchEnabled    = false
        map.showsUserLocation = false
        map.showsCompass      = false
        map.clipsToBounds     = true   // prevent CAShapeLayer trails bleeding outside this panel
        map.delegate          = ctx.coordinator

        // Carry trail — dark navy blue, matches ShotResultView.airborneColor
        let carryLayer = CAShapeLayer()
        carryLayer.strokeColor = UIColor(red: 0.05, green: 0.18, blue: 0.45, alpha: 0.90).cgColor
        carryLayer.fillColor   = UIColor.clear.cgColor
        carryLayer.lineWidth   = 2.5
        carryLayer.lineCap     = .round
        map.layer.addSublayer(carryLayer)
        ctx.coordinator.carryLayer = carryLayer

        // Rollout trail — dark green, matches ShotResultView.rolloutColor
        let rollLayer = CAShapeLayer()
        rollLayer.strokeColor = UIColor(red: 0.05, green: 0.36, blue: 0.14, alpha: 0.90).cgColor
        rollLayer.fillColor   = UIColor.clear.cgColor
        rollLayer.lineWidth   = 2.0
        rollLayer.lineCap     = .round
        map.layer.addSublayer(rollLayer)
        ctx.coordinator.rolloutLayer = rollLayer

        return map
    }

    func updateUIView(_ map: MKMapView, context ctx: Context) {
        let coord   = ctx.coordinator
        let o       = origin
        let landing = landingCoordinate
        let rollEnd = rolloutEndCoordinate

        if !coord.didSetup {
            coord.didSetup = true
            setup(map, origin: o, landing: landing)
        }

        // Re-frame whenever the map gets a real size (first layout, orientation change, etc.).
        // setup() can't do this — bounds are zero at the time it first runs.
        let currentSize = map.bounds.size
        if currentSize.width > 0, currentSize != coord.lastBoundsSize {
            coord.lastBoundsSize = currentSize
            if let o2 = o, let l2 = landing {
                frameCamera(map, origin: o2, landing: l2)
            }
        }

        guard let o, let landing else { return }

        let fp = min(max(flightProgress,  0), 1.0)
        let rp = min(max(rolloutProgress, 0), 1.0)

        // Ball position: carry phase → rollout phase.
        let ballPos: CLLocationCoordinate2D
        if rp > 0, let re = rollEnd {
            ballPos = CLLocationCoordinate2D(
                latitude:  landing.latitude  + (re.latitude  - landing.latitude)  * rp,
                longitude: landing.longitude + (re.longitude - landing.longitude) * rp
            )
        } else {
            ballPos = CLLocationCoordinate2D(
                latitude:  o.latitude  + (landing.latitude  - o.latitude)  * fp,
                longitude: o.longitude + (landing.longitude - o.longitude) * fp
            )
        }
        coord.ballAnnotation?.coordinate = ballPos

        // Update CAShapeLayer trails using screen coordinates.
        let originPt  = map.convert(o,       toPointTo: map)
        let landPt    = map.convert(landing,  toPointTo: map)
        let ballPt    = map.convert(ballPos,  toPointTo: map)

        // Carry trail: origin → ball (during carry), origin → landing (after).
        let carryEnd = fp < 1 ? ballPt : landPt
        let carryPath = UIBezierPath()
        carryPath.move(to: originPt)
        carryPath.addLine(to: carryEnd)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        coord.carryLayer?.path = carryPath.cgPath
        CATransaction.commit()

        // Rollout trail: landing → ball (during rollout).
        if rp > 0, let re = rollEnd {
            let rollPt = map.convert(re, toPointTo: map)
            let rollPos = CLLocationCoordinate2D(
                latitude:  landing.latitude  + (re.latitude  - landing.latitude)  * rp,
                longitude: landing.longitude + (re.longitude - landing.longitude) * rp
            )
            let curRollPt = map.convert(rollPos, toPointTo: map)
            let rollPath = UIBezierPath()
            rollPath.move(to: landPt)
            rollPath.addLine(to: curRollPt)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            coord.rolloutLayer?.path = rollPath.cgPath
            CATransaction.commit()
            _ = rollPt  // suppress unused warning
        }

        // Lime-green landing ring appears when ball touches down.
        let landed = fp >= 0.98
        coord.setLandingVisible(landed)
        // Hide white ball dot when at rest (lime ring takes over).
        let atRest = landed && rp >= 0.98
        coord.setBallVisible(!atRest)
    }

    // MARK: Setup

    private func setup(_ map: MKMapView,
                       origin: CLLocationCoordinate2D?,
                       landing: CLLocationCoordinate2D?) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        var path = context.holePathCoordinates
        if path.count >= 2 {
            map.addOverlay(HolePathOverlay(coordinates: &path, count: path.count),
                           level: .aboveLabels)
        }

        if let g = context.greenCenterCoordinate { map.addAnnotation(PinAnnotation(g)) }
        if let o = origin  { map.addAnnotation(BallInFlightAnnotation(o)) }
        if let l = landing { map.addAnnotation(LandingRingAnnotation(l)) }
        // frameCamera is NOT called here — bounds are zero at first updateUIView.
        // It fires from the bounds-change guard below once the map is laid out.
    }

    /// Frames the camera to show the entire hole heading-aligned (tee→green runs bottom-to-top).
    /// Mirrors the two-step approach in CourseModeGPSHoleView: build a rect with independent
    /// horizontal/vertical extents, let setVisibleMapRect compute altitude, then lock heading.
    private func frameCamera(_ map: MKMapView,
                              origin: CLLocationCoordinate2D?,
                              landing: CLLocationCoordinate2D?) {
        let tee   = context.teeCoordinate ?? context.holePathCoordinates.first ?? origin
        let green = context.greenCenterCoordinate ?? context.holePathCoordinates.last

        guard let tee, let green else { return }

        let pathCoords = context.holePathCoordinates.isEmpty ? [tee, green] : context.holePathCoordinates
        let routeStart = pathCoords.first ?? tee
        let routeEnd   = pathCoords.last  ?? green
        let heading    = GolfGeometry.bearing(from: routeStart, to: routeEnd)

        let center = CLLocationCoordinate2D(
            latitude:  (tee.latitude  + green.latitude)  / 2,
            longitude: (tee.longitude + green.longitude) / 2
        )

        // Rotate path coordinates into hole-aligned space (same math as CourseModeGPSHoleView).
        let h_rad    = heading * .pi / 180.0
        let cosLat   = cos(center.latitude * .pi / 180.0)
        let kMPerDeg = 111_320.0
        let kPad     = 30.0   // meters padding around hole

        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity
        for coord in pathCoords {
            let dn = (coord.latitude  - center.latitude)  * kMPerDeg
            let de = (coord.longitude - center.longitude) * kMPerDeg * cosLat
            let sy =  dn * cos(h_rad) + de * sin(h_rad)
            let sx = -dn * sin(h_rad) + de * cos(h_rad)
            minX = min(minX, sx); maxX = max(maxX, sx)
            minY = min(minY, sy); maxY = max(maxY, sy)
        }

        // Scale horizExtent to the panel's actual aspect ratio (width/height), so the
        // portrait hole view (tee→green runs vertically) fills the landscape panel correctly —
        // same as cropping a tall image to fit a wide frame.
        let panelW      = Double(map.bounds.width)
        let panelH      = Double(map.bounds.height)
        let panelAspect = panelW > 0 && panelH > 0 ? panelW / panelH : 1.0

        let vertExtent  = (maxY - minY) + 2 * kPad
        let horizExtent = vertExtent * panelAspect

        // Build a virtual MKMapRect with the desired extents, then let MapKit compute
        // the altitude that fits it — no assumed altitude multiplier needed.
        let ptsPerMeter = MKMapPointsPerMeterAtLatitude(center.latitude)
        let centerPt    = MKMapPoint(center)
        let fittingRect = MKMapRect(
            x: centerPt.x - (horizExtent / 2) * ptsPerMeter,
            y: centerPt.y - (vertExtent  / 2) * ptsPerMeter,
            width:  horizExtent * ptsPerMeter,
            height: vertExtent  * ptsPerMeter
        )

        map.setVisibleMapRect(fittingRect, edgePadding: .zero, animated: false)
        let alt = max(map.camera.altitude, 100.0)

        map.setCamera(MKMapCamera(lookingAtCenter: center,
                                  fromDistance: alt,
                                  pitch: 0,
                                  heading: heading),
                      animated: false)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var didSetup       = false
        var lastBoundsSize = CGSize.zero
        var carryLayer:   CAShapeLayer?
        var rolloutLayer: CAShapeLayer?
        fileprivate var ballAnnotation: BallInFlightAnnotation?
        private weak var landingView: LandingRingAnnotationView?
        private weak var ballView:    BallAnnotationView?

        func setLandingVisible(_ visible: Bool) {
            guard let v = landingView else { return }
            let target: CGFloat = visible ? 1 : 0
            guard abs(v.alpha - target) > 0.01 else { return }
            UIView.animate(withDuration: 0.20) { v.alpha = target }
            if visible { v.startPulse() }
        }

        func setBallVisible(_ visible: Bool) {
            guard let v = ballView else { return }
            let target: CGFloat = visible ? 1 : 0
            guard abs(v.alpha - target) > 0.01 else { return }
            UIView.animate(withDuration: 0.20) { v.alpha = target }
        }

        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let poly = overlay as? HolePathOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let r = MKPolylineRenderer(polyline: poly)
            r.strokeColor     = UIColor.white.withAlphaComponent(0.40)
            r.lineWidth       = 1.5
            r.lineDashPattern = [4, 5]
            return r
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let a = annotation as? BallInFlightAnnotation {
                let v = map.dequeueReusableAnnotationView(withIdentifier: "ball")
                    as? BallAnnotationView
                    ?? BallAnnotationView(annotation: a, reuseIdentifier: "ball")
                v.annotation = a
                ballAnnotation = a
                ballView = v
                return v
            }
            if let a = annotation as? LandingRingAnnotation {
                let v = map.dequeueReusableAnnotationView(withIdentifier: "landing")
                    as? LandingRingAnnotationView
                    ?? LandingRingAnnotationView(annotation: a, reuseIdentifier: "landing")
                v.annotation = a
                v.alpha = 0
                landingView = v
                return v
            }
            if annotation is PinAnnotation {
                let v = map.dequeueReusableAnnotationView(withIdentifier: "pin")
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "pin")
                v.annotation = annotation
                v.subviews.forEach { $0.removeFromSuperview() }
                let img = UIImageView(image: UIImage(systemName: "flag.fill"))
                img.tintColor = UIColor(red: 0.55, green: 0.90, blue: 0.35, alpha: 1)
                img.frame = CGRect(x: 0, y: 0, width: 14, height: 14)
                v.frame = img.frame
                v.addSubview(img)
                return v
            }
            return nil
        }
    }
}

// MARK: - Ball annotation view (white, flies along path)

private final class BallAnnotationView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        backgroundColor = .clear
        let dot = UIView(frame: bounds)
        dot.backgroundColor    = .white
        dot.layer.cornerRadius = 5
        dot.layer.shadowColor   = UIColor.white.cgColor
        dot.layer.shadowRadius  = 4
        dot.layer.shadowOpacity = 0.85
        dot.layer.shadowOffset  = .zero
        addSubview(dot)
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Landing ring annotation view (lime green, pulses at rest)

private final class LandingRingAnnotationView: MKAnnotationView {
    private let ring    = UIView()
    private let dot     = UIView()
    private var pulsing = false

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        backgroundColor = .clear

        ring.frame              = bounds
        ring.backgroundColor    = UIColor(red: 0.62, green: 1.00, blue: 0.48, alpha: 0.20)
        ring.layer.cornerRadius = 18
        ring.layer.borderColor  = UIColor(red: 0.62, green: 1.00, blue: 0.48, alpha: 0.85).cgColor
        ring.layer.borderWidth  = 1.5
        addSubview(ring)

        // Lime green center dot — matches ShotResultView.totalColor
        dot.frame              = CGRect(x: 13, y: 13, width: 10, height: 10)
        dot.backgroundColor    = UIColor(red: 0.62, green: 1.00, blue: 0.48, alpha: 1)
        dot.layer.cornerRadius = 5
        dot.layer.shadowColor  = UIColor(red: 0.40, green: 0.90, blue: 0.30, alpha: 1).cgColor
        dot.layer.shadowRadius  = 5
        dot.layer.shadowOpacity = 0.85
        dot.layer.shadowOffset  = .zero
        addSubview(dot)
    }

    required init?(coder: NSCoder) { fatalError() }

    func startPulse() {
        guard !pulsing else { return }
        pulsing = true
        UIView.animate(withDuration: 0.85, delay: 0,
                       options: [.repeat, .autoreverse, .curveEaseInOut]) {
            self.ring.transform = CGAffineTransform(scaleX: 1.40, y: 1.40)
            self.ring.alpha     = 0.30
        }
    }
}
