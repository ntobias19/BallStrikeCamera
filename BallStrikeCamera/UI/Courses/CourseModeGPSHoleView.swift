import SwiftUI
import MapKit

// MARK: - Distance Bubble Annotation

private class DistanceBubbleAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let yardage: Int
    let label: String  // "F", "C", "B"

    init(coordinate: CLLocationCoordinate2D, yardage: Int, label: String) {
        self.coordinate = coordinate
        self.yardage    = yardage
        self.label      = label
    }
}

private class DistanceBubbleAnnotationView: MKAnnotationView {
    private let bubbleLabel = UILabel()
    private let container   = UIView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 68, height: 30)
        centerOffset = CGPoint(x: 0, y: -15)
        backgroundColor = .clear
        setupBubble()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupBubble() {
        container.backgroundColor = UIColor(white: 0.05, alpha: 0.82)
        container.layer.cornerRadius = 12
        container.layer.borderWidth  = 1
        container.layer.borderColor  = UIColor(white: 1.0, alpha: 0.18).cgColor
        container.frame = bounds
        addSubview(container)

        bubbleLabel.textColor     = .white
        bubbleLabel.font          = UIFont.systemFont(ofSize: 13, weight: .bold)
        bubbleLabel.textAlignment = .center
        bubbleLabel.frame         = container.bounds
        container.addSubview(bubbleLabel)
    }

    override var annotation: MKAnnotation? {
        didSet {
            guard let a = annotation as? DistanceBubbleAnnotation else { return }
            bubbleLabel.text = "\(a.label) \(a.yardage)"
            sizeToFit()
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let a = annotation as? DistanceBubbleAnnotation else { return CGSize(width: 68, height: 30) }
        let text  = "\(a.label) \(a.yardage)"
        let attrs = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 13, weight: .bold)]
        let w     = (text as NSString).size(withAttributes: attrs).width + 24
        return CGSize(width: max(w, 56), height: 30)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        container.frame    = bounds
        bubbleLabel.frame  = container.bounds
        centerOffset       = CGPoint(x: 0, y: -bounds.height / 2)
    }
}

// MARK: - Flag / Pin Annotation

private class GreenPinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
    var title: String? { "Pin" }
}

// MARK: - Satellite Map Background

private struct SatelliteMapBackground: UIViewRepresentable {
    var greenCoord:  CLLocationCoordinate2D?
    var userCoord:   CLLocationCoordinate2D?
    var courseCoord: CLLocationCoordinate2D?
    var frontCoord:  CLLocationCoordinate2D?
    var backCoord:   CLLocationCoordinate2D?
    var frontDist:   Int?
    var centerDist:  Int?
    var backDist:    Int?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType             = .hybrid
        map.isScrollEnabled     = false
        map.isZoomEnabled       = false
        map.isRotateEnabled     = false
        map.isPitchEnabled      = false
        map.showsUserLocation   = true
        map.showsCompass        = false
        map.delegate            = context.coordinator
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })

        // Region
        if let green = greenCoord, let user = userCoord {
            let midLat  = (green.latitude  + user.latitude)  / 2
            let midLon  = (green.longitude + user.longitude) / 2
            let spanLat = max(abs(green.latitude  - user.latitude)  * 1.55, 0.0019)
            let spanLon = max(abs(green.longitude - user.longitude) * 1.55, 0.0019)
            map.setRegion(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
                    span:   MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
                ),
                animated: true
            )
            // Line from user to green
            var pts = [user, green]
            map.addOverlay(MKPolyline(coordinates: &pts, count: 2))
        } else if let green = greenCoord {
            map.setRegion(
                MKCoordinateRegion(center: green,
                                   latitudinalMeters: 400,
                                   longitudinalMeters: 400),
                animated: false
            )
        } else {
            // Always center on the course/hole — never follow the user's GPS alone
            let center = courseCoord ?? CLLocationCoordinate2D(latitude: 37.785834, longitude: -122.406417)
            map.setRegion(
                MKCoordinateRegion(center: center,
                                   latitudinalMeters: 400,
                                   longitudinalMeters: 400),
                animated: false
            )
        }

        // Yellow flag at green center
        if let green = greenCoord {
            map.addAnnotation(GreenPinAnnotation(coordinate: green))
        }

        // Distance bubble annotations
        if let coord = frontCoord, let dist = frontDist {
            map.addAnnotation(DistanceBubbleAnnotation(coordinate: coord, yardage: dist, label: "F"))
        }
        if let coord = greenCoord, let dist = centerDist {
            // Offset the center bubble slightly so it doesn't stack on the flag
            let offsetCoord = CLLocationCoordinate2D(
                latitude:  coord.latitude  + 0.00005,
                longitude: coord.longitude - 0.00010
            )
            map.addAnnotation(DistanceBubbleAnnotation(coordinate: offsetCoord, yardage: dist, label: "C"))
        }
        if let coord = backCoord, let dist = backDist {
            map.addAnnotation(DistanceBubbleAnnotation(coordinate: coord, yardage: dist, label: "B"))
        }
    }

    // MARK: Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r            = MKPolylineRenderer(polyline: line)
            r.strokeColor    = UIColor(white: 1.0, alpha: 0.92)
            r.lineWidth      = 2.5
            r.lineDashPattern = [5, 4]
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }

            if let pin = annotation as? GreenPinAnnotation {
                let id  = "greenPin"
                let v   = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                            as? MKMarkerAnnotationView
                            ?? MKMarkerAnnotationView(annotation: pin, reuseIdentifier: id)
                v.annotation     = pin
                v.markerTintColor = UIColor(red: 1.0, green: 0.82, blue: 0.0, alpha: 1.0)
                v.glyphImage      = UIImage(systemName: "flag.fill")
                v.glyphTintColor  = .black
                v.displayPriority = .required
                return v
            }

            if let bubble = annotation as? DistanceBubbleAnnotation {
                let id  = "distBubble"
                let v   = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                            as? DistanceBubbleAnnotationView
                            ?? DistanceBubbleAnnotationView(annotation: bubble, reuseIdentifier: id)
                v.annotation      = bubble
                v.displayPriority = .required
                v.setNeedsLayout()
                v.layoutIfNeeded()
                return v
            }

            return nil
        }
    }
}

// MARK: - Main View

struct CourseModeGPSHoleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AuthSessionStore
    @EnvironmentObject var camera: CameraController
    @StateObject private var vm: CourseRoundViewModel

    @State private var showCamera      = false
    @State private var showScoreEntry  = false
    @State private var showScorecard   = false
    @State private var showFinishAlert = false
    @State private var gpsOn           = true
    @State private var infoMessage: String?
    @State private var roundStartTime  = Date()

    let initialCourse: GolfCourse?
    let initialTeeBox: TeeBox?

    // MARK: Computed Properties

    private var currentCourseHole: GolfHole? {
        guard let hole = vm.currentHole,
              let course = vm.selectedCourse else { return nil }
        return course.holes.first { $0.number == hole.holeNumber }
    }

    private var scorecardYardage: Int? {
        guard let gh = currentCourseHole,
              let tee = vm.selectedTeeBox else { return nil }
        return gh.teeYardsByTeeBox[tee.id]
    }

    private var gpsDistances: GreenDistances {
        guard let gh = currentCourseHole else { return GreenDistances() }
        return vm.location.greenDistances(
            front:  gh.greenFrontCoordinate?.clCoordinate,
            center: gh.greenCenterCoordinate?.clCoordinate,
            back:   gh.greenBackCoordinate?.clCoordinate
        )
    }

    private var displayYardage: Int? {
        if gpsOn, let gps = gpsDistances.center { return gps }
        return scorecardYardage
    }

    private var holeHandicap: Int {
        guard let hole = vm.currentHole,
              let gh = vm.selectedCourse?.holes.first(where: { $0.number == hole.holeNumber })
        else { return vm.currentHole?.par == 3 ? 9 : 7 }
        return gh.handicap ?? 9
    }

    private var userName: String { session.userProfile?.displayName ?? "Player" }

    private var userInitials: String {
        let parts = userName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].first ?? "P").uppercased()
                 + String(parts[1].first ?? "L").uppercased()
        }
        return String(userName.prefix(2)).uppercased()
    }

    private var topSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 44
    }

    private var timeElapsed: String {
        let elapsed = Int(Date().timeIntervalSince(roundStartTime))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private var scoreToPar: Int {
        (vm.activeRound?.scoreSummary.totalScore ?? 0)
      - (vm.activeRound?.scoreSummary.totalPar   ?? 0)
    }

    private var scoreToParString: String {
        if scoreToPar == 0 { return "E" }
        return scoreToPar > 0 ? "+\(scoreToPar)" : "\(scoreToPar)"
    }

    private var scoreToParColor: Color {
        scoreToPar < 0 ? Color(red: 0.22, green: 0.78, blue: 0.42)
            : scoreToPar == 0 ? Color(red: 0.42, green: 0.72, blue: 0.98)
            : TCTheme.textMuted
    }

    // MARK: - Init

    init(userId: UUID, backend: AppBackend,
         initialCourse: GolfCourse? = nil,
         initialTeeBox: TeeBox? = nil) {
        _vm = StateObject(wrappedValue: CourseRoundViewModel(userId: userId, backend: backend))
        self.initialCourse = initialCourse
        self.initialTeeBox = initialTeeBox
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {

            // Full-screen satellite map
            SatelliteMapBackground(
                greenCoord:  currentCourseHole?.greenCenterCoordinate?.clCoordinate,
                userCoord:   gpsOn ? vm.location.currentLocation : nil,
                courseCoord: vm.selectedCourse?.coordinate ?? initialCourse?.coordinate,
                frontCoord:  currentCourseHole?.greenFrontCoordinate?.clCoordinate,
                backCoord:   currentCourseHole?.greenBackCoordinate?.clCoordinate,
                frontDist:   gpsOn ? gpsDistances.front  : nil,
                centerDist:  gpsOn ? gpsDistances.center : nil,
                backDist:    gpsOn ? gpsDistances.back   : nil
            )
            .ignoresSafeArea()

            // Top dark gradient
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.72), Color.black.opacity(0.36), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 200)
                .ignoresSafeArea(edges: .top)
                Spacer()
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.85)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 220)
            }
            .ignoresSafeArea()

            // ── Layout layers ──────────────────────────────────────────────
            VStack(spacing: 0) {

                // Top bar
                topBar
                    .padding(.top, topSafeArea + 4)

                // Hole info strip
                holeInfoStrip
                    .padding(.top, 6)
                    .padding(.horizontal, 16)

                Spacer()
            }
            .ignoresSafeArea(edges: .bottom)

            // Left sidebar
            leftSidebar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.top, topSafeArea + 100)
                .padding(.bottom, 200)
                .ignoresSafeArea(edges: .bottom)

            // Right sidebar
            rightSidebar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
                .padding(.top, topSafeArea + 100)
                .padding(.bottom, 200)
                .ignoresSafeArea(edges: .bottom)
        }
        // Bottom bar
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarHidden(true)
        // Alerts
        .alert("Finish Round?", isPresented: $showFinishAlert) {
            Button("Finish & Save", role: .destructive) {
                Task { await vm.finishRound(); dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your round will be saved.")
        }
        .alert("Course Tool", isPresented: Binding(
            get:  { infoMessage != nil },
            set:  { if !$0 { infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoMessage ?? "")
        }
        // Sheets
        .fullScreenCover(isPresented: $showCamera) {
            RangeCameraScreen(
                shotCount: vm.activeRound?.shotIds.count ?? 0,
                context:   buildContext(),
                onShotSaved: { shot in Task { await vm.addShot(shot) } }
            )
            .ignoresSafeArea()
            .statusBarHidden(true)
        }
        .sheet(isPresented: $showScoreEntry) {
            if let hole = vm.currentHole {
                ScoreEntryView(
                    holeNumber:     hole.holeNumber,
                    par:            hole.par,
                    existingScore:  hole.score,
                    existingPutts:  hole.putts,
                    holeYardage:    scorecardYardage,
                    handicap:       currentCourseHole?.handicap
                ) { s, p, f, g in
                    let idx = vm.currentHoleIndex
                    Task { await vm.setScore(holeIndex: idx, score: s, putts: p, fairwayHit: f, gir: g) }
                }
                .preferredColorScheme(.dark)
            }
        }
        .sheet(isPresented: $showScorecard) {
            if let round = vm.activeRound {
                NavigationStack {
                    ScorecardView(round: round, course: vm.selectedCourse)
                }
                .preferredColorScheme(.dark)
            }
        }
        .task {
            if let course = initialCourse, let tee = initialTeeBox {
                await vm.startRound(course: course, teeBox: tee)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            // Back / X button
            Button { showFinishAlert = true } label: {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.52))
                        .frame(width: 36, height: 36)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Center: chevron + HOLE NUMBER + chevron
            HStack(spacing: 10) {
                Button {
                    if vm.currentHoleIndex > 0 { vm.goToHole(vm.currentHoleIndex - 1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.80))
                }
                .buttonStyle(.plain)

                if let hole = vm.currentHole {
                    Text(ordinal(hole.holeNumber).uppercased())
                        .font(.system(size: 17, weight: .black))
                        .foregroundColor(.white)
                        .frame(minWidth: 52)
                } else {
                    Text("—")
                        .font(.system(size: 17, weight: .black))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(minWidth: 52)
                }

                Button {
                    if let round = vm.activeRound, vm.currentHoleIndex < round.holes.count - 1 {
                        vm.advanceHole()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.80))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // GPS signal icon
            Button { gpsOn.toggle() } label: {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.52))
                        .frame(width: 36, height: 36)
                    Image(systemName: gpsOn ? "location.fill" : "location.slash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(gpsOn ? Color(red: 0.22, green: 0.84, blue: 0.46) : .white.opacity(0.45))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Hole Info Strip

    private var holeInfoStrip: some View {
        Group {
            if let hole = vm.currentHole {
                let parStr  = "Par \(hole.par)"
                let ydsStr  = scorecardYardage.map { "\($0) yds" } ?? "— yds"
                let hcpStr  = "Hcp \(holeHandicap)"
                Text("\(parStr)  ·  \(ydsStr)  ·  \(hcpStr)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.90))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.50))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Left Sidebar

    private var leftSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {

            // GPS signal card
            sideCard {
                HStack(spacing: 5) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(gpsOn ? Color(red: 0.22, green: 0.84, blue: 0.46) : .white.opacity(0.35))
                    Text(gpsOn ? "GPS" : "GPS OFF")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                    if gpsOn {
                        HStack(spacing: 2) {
                            ForEach(0..<4, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color(red: 0.22, green: 0.84, blue: 0.46))
                                    .frame(width: 3, height: CGFloat(5 + i * 2))
                            }
                        }
                    }
                }
            }

            // Compass widget
            sideCard {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                        .frame(width: 32, height: 32)
                    VStack(spacing: 0) {
                        Text("N")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(Color(red: 0.95, green: 0.28, blue: 0.28))
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 8))
                            .foregroundColor(Color(red: 0.95, green: 0.28, blue: 0.28))
                    }
                }
            }

            // Round timer
            sideCard {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.55))
                        Text(timeElapsed)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.90))
                    }
                    let holeCount = min(vm.currentHoleIndex, (vm.activeRound?.holes.count ?? 18))
                    Text("thru \(holeCount)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.45))
                }
            }

            // Distance card — only when GPS active
            if gpsOn && gpsDistances.isAvailable {
                sideCard {
                    VStack(alignment: .leading, spacing: 3) {
                        if let f = gpsDistances.front {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.45))
                                Text("\(f)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                        }
                        if let c = gpsDistances.center {
                            Text("\(c)")
                                .font(.system(size: 16, weight: .black))
                                .foregroundColor(.white)
                        }
                        if let b = gpsDistances.back {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.45))
                                Text("\(b)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// Dark pill card wrapper used in the left sidebar
    @ViewBuilder
    private func sideCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )
    }

    // MARK: - Right Sidebar

    private var rightSidebar: some View {
        VStack(spacing: 8) {
            toolButton("ruler.fill",          "Measure")
            toolButton("target",              "Targets")
            toolButton("arrow.down.to.line",  "Layup")
            toolButton("circle.fill",         "Green")
            toolButton("list.number",         "Card")   { showScorecard = true }
            toolButton("flag.checkered",      "Finish") { showFinishAlert = true }
            Spacer(minLength: 0)
        }
    }

    private func toolButton(_ icon: String, _ label: String, action: (() -> Void)? = nil) -> some View {
        Button {
            if let a = action { a() }
            else { infoMessage = "\(label) is ready for the course overlay once GPS target data is available." }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.80))
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.white.opacity(0.50))
            }
            .frame(width: 44, height: 44)
            .background(Color.black.opacity(0.55))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 14) {
            // Player avatar + name + score
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(TCTheme.panelRaised)
                        .frame(width: 38, height: 38)
                    Circle()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1.5)
                        .frame(width: 38, height: 38)
                    Text(userInitials)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(userName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    HStack(spacing: 5) {
                        Text(scoreToParString)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(scoreToParColor)
                        Text("·  Hole \(vm.currentHoleIndex + 1)/\(vm.activeRound?.holes.count ?? 18)")
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.textMuted)
                    }
                }
            }

            Spacer()

            // Add Score button
            Button { showScoreEntry = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Add Score")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.60))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(.ultraThinMaterial.opacity(0.25))
        .background(Color.black.opacity(0.78))
        .overlay(Rectangle().fill(.white.opacity(0.07)).frame(height: 1), alignment: .top)
    }

    // MARK: - Helpers

    private func buildContext() -> ShotContext {
        ShotContext(
            sourceMode:    .course,
            courseRoundId: vm.activeRound?.id,
            holeNumber:    vm.currentHole?.holeNumber,
            holePar:       vm.currentHole?.par,
            holeYardage:   scorecardYardage,
            courseName:    vm.activeRound?.courseName,
            holeHandicap:  holeHandicap
        )
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n {
        case 11, 12, 13: suffix = "th"
        default:
            switch n % 10 {
            case 1:  suffix = "st"
            case 2:  suffix = "nd"
            case 3:  suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}
