#if DEBUG
import SwiftUI
import UIKit

// MARK: - Root

struct BallTrackingTestView: View {
    let onDismiss: () -> Void

    enum TesterPage: String, CaseIterable {
        case ball    = "Ball"
        case club    = "Club"
        case metrics = "Metrics"
    }

    @State private var exports:           [URL]                      = []
    @State private var sequence:          BallTrackingTestSequence?  = nil
    @State private var result:            BallTrackingTestResult?    = nil
    @State private var isRunning:         Bool                       = false
    @State private var currentIndex:      Int                        = 0
    @State private var clubCurrentIndex:  Int                        = 0
    @State private var loadError:         String?                    = nil
    @State private var displayMode:       FrameNormalizationMode     = .darkenedHighContrast
    @State private var settings:          BallTrackingTuningSettings = BallTrackingTuningSettings()
    @State private var exportStatus:      String?                    = nil
    @State private var activePage:        TesterPage                 = .ball

    private let loader     = TestFrameLoader()
    private let normalizer = FrameNormalizer()

    // Effective impact index: detected (after Run) or metadata fallback
    private var effectiveImpactIndex: Int {
        result?.detectedImpactFrameIndex ?? sequence?.impactFrameIndex ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let seq = sequence {
                mainContent(seq)
            } else {
                exportList
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { exports = loader.listAvailableExports() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            if sequence != nil {
                Button(action: { sequence = nil; result = nil }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            Text(sequence.map { "Tester · \($0.sourceName)" } ?? "Tracking Tester")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white).lineLimit(1).truncationMode(.middle)
            Spacer()
            if sequence != nil {
                pagePicker
                if activePage == .ball { displayModePicker }
                Button(action: runTracker) {
                    Label(isRunning ? "Running…" : "Run", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(isRunning ? Color.gray.opacity(0.5) : Color.purple.opacity(0.75))
                        .clipShape(Capsule())
                }
                .disabled(isRunning)
                Button(action: exportExperimentalMetrics) {
                    Label("Export Metrics", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(result?.metrics == nil ? Color.gray.opacity(0.45) : Color.orange.opacity(0.75))
                        .clipShape(Capsule())
                }
                .disabled(result?.metrics == nil)
            }
            Button("Done") { onDismiss() }
                .font(.system(size: 14, weight: .semibold)).foregroundColor(.blue)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(white: 0.10))
    }

    private var pagePicker: some View {
        HStack(spacing: 0) {
            ForEach(TesterPage.allCases, id: \.self) { page in
                Button(action: { activePage = page }) {
                    Text(page.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(activePage == page ? .black : .white.opacity(0.65))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(activePage == page ? Color.white : Color.clear)
                }
            }
        }
        .background(Color.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var displayModePicker: some View {
        HStack(spacing: 0) {
            ForEach(FrameNormalizationMode.allCases, id: \.self) { mode in
                Button(action: { displayMode = mode }) {
                    Text(mode.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(displayMode == mode ? .black : .white.opacity(0.65))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(displayMode == mode ? Color.white : Color.clear)
                }
            }
        }
        .background(Color.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - Export list

    private var exportList: some View {
        Group {
            if exports.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.system(size: 36)).foregroundColor(.white.opacity(0.3))
                    Text("No shot exports found").font(.system(size: 14)).foregroundColor(.white.opacity(0.5))
                    Text("Export a shot from the Review screen first.")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(exports, id: \.self) { url in
                            Button(action: { loadExport(url) }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                                        if let count = frameCount(in: url) {
                                            Text("\(count) frames")
                                                .font(.system(size: 11)).foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12)).foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(Color(white: 0.10))
                            }
                        }
                    }
                }
                .padding(.top, 1)
            }
        }
    }

    // MARK: - Main content

    private func mainContent(_ seq: BallTrackingTestSequence) -> some View {
        Group {
            switch activePage {
            case .ball:    ballPage(seq)
            case .club:    clubPage(seq)
            case .metrics: metricsPage
            }
        }
    }

    private func ballPage(_ seq: BallTrackingTestSequence) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                imagePane(seq).frame(maxWidth: .infinity)
                controlsSidebar.frame(width: 270)
            }
            .layoutPriority(1)
            impactInfoRow
            metricsInfoRow
            frameStrip(seq)
            navigationBar(seq)
        }
        .background(
            KeyboardNavigatorView(
                onLeft:  { if currentIndex > 0 { currentIndex -= 1 } },
                onRight: { if currentIndex < (sequence?.frames.count ?? 1) - 1 { currentIndex += 1 } }
            ).frame(width: 0, height: 0)
        )
    }

    // MARK: - Club page

    private func clubPage(_ seq: BallTrackingTestSequence) -> some View {
        let impact = effectiveImpactIndex
        let clubFrames = seq.frames.filter { $0.frameIndex >= impact - 10 && $0.frameIndex <= impact + 1 }
        let clubCount = clubFrames.count
        let safeIdx = min(clubCurrentIndex, max(0, clubCount - 1))

        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                // Club image pane
                GeometryReader { geo in
                    ZStack {
                        Color.black
                        if safeIdx < clubFrames.count,
                           let img = displayedImage(clubFrames[safeIdx]) {
                            Image(uiImage: img).resizable().scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            let fi = clubFrames[safeIdx].frameIndex
                            let clubObs = result?.metrics?.clubObservations.first { $0.frameIndex == fi }
                            Canvas { ctx, size in
                                let dr = aspectFitRect(imageSize: img.size, in: size)
                                guard dr.width > 0 else { return }
                                drawClubPageOverlay(ctx: ctx, dr: dr, metrics: result?.metrics,
                                                    clubObs: clubObs, frameIndex: fi)
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .allowsHitTesting(false)
                            clubInfoOverlay(frame: clubFrames[safeIdx], clubObs: clubObs, impact: impact)
                            clubOverlayLegend
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .padding(.top, 8).padding(.trailing, 8)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                clubControlsSidebar.frame(width: 270)
            }
            .layoutPriority(1)
            clubFrameStrip(clubFrames, impact: impact)
            clubNavigationBar(clubCount)
        }
        .background(
            KeyboardNavigatorView(
                onLeft:  { if clubCurrentIndex > 0 { clubCurrentIndex -= 1 } },
                onRight: { if clubCurrentIndex < clubCount - 1 { clubCurrentIndex += 1 } }
            ).frame(width: 0, height: 0)
        )
    }

    private func drawClubPageOverlay(
        ctx: GraphicsContext,
        dr: CGRect,
        metrics: ExperimentalShotMetricsResult?,
        clubObs: ExperimentalClubObservation?,
        frameIndex: Int
    ) {
        // Orange solid club center path, built up to the current frame
        if settings.club.showClubPath,
           let allObs = metrics?.clubObservations.filter({ $0.isDetected && $0.frameIndex <= frameIndex }),
           allObs.count >= 2 {
            var path = Path()
            var started = false
            for obs in allObs {
                guard let x = obs.centerX, let y = obs.centerY else { continue }
                let pt = normPointToView(CGPoint(x: x, y: y), dr: dr)
                if started { path.addLine(to: pt) } else { path.move(to: pt); started = true }
            }
            // Orange solid line through clubhead centers (smooth, no zig-zag)
            ctx.stroke(path, with: .color(.orange.opacity(0.9)), style: StrokeStyle(lineWidth: 2))

            // Dot at each detected center; emphasize current frame
            for obs in allObs {
                guard let x = obs.centerX, let y = obs.centerY else { continue }
                let pt = normPointToView(CGPoint(x: x, y: y), dr: dr)
                let isCurrent = obs.frameIndex == frameIndex
                let r: CGFloat = isCurrent ? 5.5 : 3
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                         with: .color(.orange.opacity(isCurrent ? 1.0 : 0.65)))
            }
        }

        // 0° HLA reference line from impact ball position
        if settings.show0DegRef {
            let origin: CGPoint?
            if let impactObs = metrics?.clubObservations.first(where: {
                $0.ballExclusionCenterX != nil && $0.frameDifferenceWasUsed == false || true
            }), let bx = impactObs.ballExclusionCenterX, let by = impactObs.ballExclusionCenterY {
                origin = normPointToView(CGPoint(x: bx, y: by), dr: dr)
            } else if let firstBall = metrics?.ball3DObservations.first {
                origin = normPointToView(CGPoint(x: firstBall.imageX, y: firstBall.imageY), dr: dr)
            } else {
                origin = nil
            }
            if let origin {
                draw0DegRef(ctx: ctx, dr: dr, origin: origin, zeroDeg: settings.zeroDegreeAngleDeg)
            }
        }

        guard let clubObs else { return }

        if settings.club.showClubSearchROI, let roi = clubObs.searchROI {
            ctx.stroke(Path(normToView(roi, dr: dr)), with: .color(.orange.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }

        if settings.club.showBallExclusionZone,
           let x = clubObs.ballExclusionCenterX, let y = clubObs.ballExclusionCenterY,
           let d = clubObs.ballExclusionDiameter {
            strokeCircle(ctx: ctx, dr: dr, cx: x, cy: y, d: d, color: .orange.opacity(0.32), lineWidth: 1)
        }

        // Orange bounding box around clubhead
        if let bbox = clubObs.clubBoundingBox {
            ctx.stroke(Path(normToView(bbox, dr: dr)), with: .color(.orange.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 2))
        }

        if let cx = clubObs.centerX, let cy = clubObs.centerY {
            let pt = normPointToView(CGPoint(x: cx, y: cy), dr: dr)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)),
                     with: .color(.orange))
        }

        if let lx = clubObs.leadingEdgeX, let ly = clubObs.leadingEdgeY {
            let pt = normPointToView(CGPoint(x: lx, y: ly), dr: dr)
            ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)),
                       with: .color(.purple), lineWidth: 2.5)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)),
                     with: .color(.purple))
        }
    }

    private func clubInfoOverlay(frame: BallTrackingTestFrame,
                                  clubObs: ExperimentalClubObservation?,
                                  impact: Int) -> some View {
        let fi = frame.frameIndex
        let rel = fi - impact
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("Frame \(fi)").fontWeight(.semibold)
                Text(rel == 0 ? "IMPACT" : rel < 0 ? "pre \(rel)" : "post +\(rel)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(rel == 0 ? .red : rel < 0 ? .secondary : .orange)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background((rel == 0 ? Color.red : rel < 0 ? Color.secondary : Color.orange).opacity(0.2))
                    .clipShape(Capsule())
                Text(String(format: "%+.1f ms", frame.relativeTime * 1000)).foregroundColor(.secondary)
            }
            if let c = clubObs, c.isDetected {
                if let lx = c.leadingEdgeX, let ly = c.leadingEdgeY {
                    Text(String(format: "lead=(%.4f, %.4f) conf=%.2f", lx, ly, c.confidence))
                        .foregroundColor(.orange)
                }
                if let bbox = c.clubBoundingBox {
                    Text(String(format: "bbox=(%.3f,%.3f,%.3f,%.3f)", bbox.minX, bbox.minY, bbox.width, bbox.height))
                        .foregroundColor(.white.opacity(0.6))
                }
                Text("mode=\(c.detectionMode)  diff=\(c.frameDifferenceWasUsed ? "yes" : "no")")
                    .foregroundColor(.white.opacity(0.45))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    Text(clubObs?.debugReason ?? (result == nil ? "Run tracker first" : "no club obs")).foregroundColor(.orange)
                }
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.white)
        .padding(8).background(Color.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var clubOverlayLegend: some View {
        let items: [(String, Color)] = [
            ("── Club center path", .orange),
            ("- - Club search ROI", .orange),
            ("□  Clubhead bounding box", .orange),
            ("◉  Leading edge point", .purple),
            ("- - 0° HLA reference", .white),
            ("○  Ball exclusion zone", .orange.opacity(0.5))
        ]
        return VStack(alignment: .leading, spacing: 2) {
            Text("LEGEND")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white.opacity(0.55))
            ForEach(items, id: \.0) { label, color in
                Text(label)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(color)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.80))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func clubFrameStrip(_ frames: [BallTrackingTestFrame], impact: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(frames.enumerated()), id: \.offset) { i, frame in
                        let fi = frame.frameIndex
                        let isImpact = fi == impact
                        let detected = result?.metrics?.clubObservations.first {
                            $0.frameIndex == fi && $0.isDetected
                        } != nil
                        let color: Color = isImpact ? .yellow : detected ? .orange : result != nil ? .red.opacity(0.6) : Color(white: 0.25)
                        Button(action: { clubCurrentIndex = i }) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color.opacity(0.85))
                                .frame(width: 18, height: 32)
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white, lineWidth: clubCurrentIndex == i ? 2 : 0))
                                .overlay(alignment: .top) {
                                    Text("\(fi)").font(.system(size: 7)).foregroundColor(.white.opacity(0.7)).padding(.top, 2)
                                }
                        }
                        .id(i)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 44)
            .background(Color(white: 0.08))
            .onChange(of: clubCurrentIndex) { idx in
                withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(idx, anchor: .center) }
            }
        }
    }

    private func clubNavigationBar(_ count: Int) -> some View {
        let last = max(0, count - 1)
        return HStack(spacing: 12) {
            Button(action: { if clubCurrentIndex > 0 { clubCurrentIndex -= 1 } }) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .foregroundColor(clubCurrentIndex > 0 ? .white : .white.opacity(0.25))
            }.frame(width: 44, height: 44)
            Slider(value: Binding(
                get: { Double(clubCurrentIndex) },
                set: { clubCurrentIndex = Int($0.rounded()) }
            ), in: 0...Double(max(1, last)), step: 1).tint(.orange)
            Button(action: { if clubCurrentIndex < last { clubCurrentIndex += 1 } }) {
                Image(systemName: "chevron.right").font(.system(size: 18, weight: .semibold))
                    .foregroundColor(clubCurrentIndex < last ? .white : .white.opacity(0.25))
            }.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(white: 0.10))
    }

    private var clubControlsSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                TunerSection(title: "Club Detection") {
                    TunerToggle(label: "enabled", value: $settings.club.enabled)
                    TunerToggle(label: "search behind ball", value: $settings.club.searchBehindBallEnabled)
                    TunerSlider(label: "ball excl scale", value: $settings.club.ballExclusionRadiusScale,
                                range: 0.5...5.0, format: "%.2f")
                    TunerSlider(label: "ROI scale X", value: $settings.club.clubSearchROIScaleX,
                                range: 1...16, format: "%.2f")
                    TunerSlider(label: "ROI scale Y", value: $settings.club.clubSearchROIScaleY,
                                range: 1...12, format: "%.2f")
                }
                TunerSection(title: "Frame Difference") {
                    TunerToggle(label: "use frame diff", value: $settings.club.useFrameDifference)
                    TunerSlider(label: "diff threshold", value: $settings.club.frameDifferenceThreshold,
                                range: 1...120, format: "%.0f", isInt: true)
                }
                TunerSection(title: "Dark Blob") {
                    TunerSlider(label: "darkness threshold", value: $settings.club.minClubDarknessOrEdgeThreshold,
                                range: 10...180, format: "%.0f", isInt: true)
                    TunerSlider(label: "min blob area", value: $settings.club.minClubBlobArea,
                                range: 1...300, format: "%.0f", isInt: true)
                    TunerSlider(label: "max blob area", value: $settings.club.maxClubBlobArea,
                                range: 100...20000, format: "%.0f", isInt: true)
                    TunerSlider(label: "min confidence", value: $settings.club.minClubConfidence,
                                range: 0...1, format: "%.2f")
                }
                TunerSection(title: "Overlays") {
                    TunerToggle(label: "show club path",     value: $settings.club.showClubPath)
                    TunerToggle(label: "show club ROI",      value: $settings.club.showClubSearchROI)
                    TunerToggle(label: "show exclusion zone",value: $settings.club.showBallExclusionZone)
                    TunerToggle(label: "show 0° ref line",   value: $settings.show0DegRef)
                    TunerToggle(label: "debug logging",      value: $settings.club.debugLoggingEnabled)
                }
                if let metrics = result?.metrics {
                    TunerSection(title: "Club Results") {
                        clubMetricReadout("Club speed", value: mph(metrics.club.clubSpeedMph))
                        clubMetricReadout("Points used", value: "\(metrics.club.pointsUsed)")
                        clubMetricReadout("Quality", value: String(format: "%.2f", metrics.club.quality))
                        clubMetricReadout("Method", value: metrics.club.method)
                        ForEach(metrics.club.warnings, id: \.self) { w in
                            Text("⚠ \(w)").font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.yellow).padding(.horizontal, 12).padding(.vertical, 2)
                        }
                    }
                }
                Button(action: { settings.club.resetDefaults() }) {
                    Text("Reset club defaults").font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
            }
            .padding(.bottom, 20)
        }
        .background(Color(white: 0.07))
    }

    private func clubMetricReadout(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 3)
    }

    // MARK: - Metrics page

    private var metricsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let metrics = result?.metrics {
                    metricsResults(metrics)
                } else if result != nil {
                    Text("Run tracker to populate metrics.\n(Metrics run automatically with tracking.)")
                        .font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
                        .padding(24)
                } else {
                    Text("Press Run to calculate metrics.")
                        .font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
                        .padding(24)
                }
                Divider().background(Color.white.opacity(0.1)).padding(.vertical, 12)
                metricsFormulas
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
        .background(Color.black)
    }

    private func metricsResults(_ metrics: ExperimentalShotMetricsResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RESULTS").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)

            metricsGroup("Ball Launch") {
                metricsRow("Ball Speed", value: mph(metrics.ballLaunch.ballSpeedMph),
                           formula: "|v_ball| × 2.23694",
                           note: "\(metrics.ballLaunch.pointsUsed) pts · \(metrics.ballLaunch.method)")
                metricsRow("HLA",
                           value: metrics.ballLaunch.hlaDisplay,
                           formula: "atan2(lateral, forward) — image-space ref \(String(format: "%.0f°", metrics.zeroDegreeReferenceAngleDegrees))",
                           note: "3D raw: \(degrees(metrics.ballLaunch.hla3DRawDegrees))")
                metricsRow("VLA", value: degrees(metrics.ballLaunch.vlaDegrees),
                           formula: "atan2(vy, √(vx²+vz²))", note: "vertical launch angle")
                if let dx = metrics.ballLaunch.ballMovementDx, let dy = metrics.ballLaunch.ballMovementDy {
                    metricsRow("2D movement",
                               value: String(format: "(%.4f, %.4f)", dx, dy),
                               formula: "image-space dx/dt, dy/dt (x→, y↓)", note: nil)
                }
                if let fwd = metrics.ballLaunch.hlaForwardComponent,
                   let lat = metrics.ballLaunch.hlaLateralComponent {
                    metricsRow("Fwd / Lateral",
                               value: String(format: "%.4f / %.4f", fwd, lat),
                               formula: "projected onto ref / perp axes", note: nil)
                }
            }

            metricsGroup("Club") {
                metricsRow("Club Speed", value: mph(metrics.club.clubSpeedMph),
                           formula: "|v_club| × 2.23694",
                           note: "\(metrics.club.pointsUsed) pts · assumed ball depth · frameDifference mode")
                metricsRow("Smash Factor", value: plain(metrics.smashFactor, digits: 2),
                           formula: "ball_speed / club_speed", note: nil)
                metricsRow("Club Path (Estimated)",
                           value: metrics.clubPath.clubPathDisplay,
                           formula: "image-space 2D movement → atan2 vs 0° ref",
                           note: String(format: "conf %.2f · %@", metrics.clubPath.confidence, metrics.clubPath.method))
                metricsRow("Face Angle (Estimated)",
                           value: metrics.faceAngle.faceAngleDisplay,
                           formula: "edge gradient PCA in clubhead bbox",
                           note: "confidence: \(metrics.faceAngle.confidence)")
                metricsRow("Face-to-Path (Estimated)",
                           value: metrics.faceAngle.faceToPathDisplay,
                           formula: "face − club path  (+R = open, −L = closed)",
                           note: nil)
            }

            metricsGroup("Estimated Spin (Model-Based)") {
                metricsRow("Backspin (Estimated)",
                           value: metrics.spin.estimatedBackspinRpm.map { String(format: "%.0f rpm", $0) } ?? "—",
                           formula: "(800 + 90×speed + 120×VLA) × VLA_multiplier",
                           note: "ESTIMATED — not measured")
                metricsRow("Sidespin (Estimated)",
                           value: metrics.spin.estimatedSidespinDisplay,
                           formula: "(HLA − path) × 200 × (speed/100)",
                           note: "ESTIMATED · \(metrics.spin.spinEstimateMethod)")
                metricsRow("Spin Axis (Estimated)",
                           value: metrics.spin.estimatedSpinAxisDisplay,
                           formula: "atan2(sidespin, backspin)",
                           note: "ESTIMATED — positive = tilted right")
            }

            metricsGroup("Distance") {
                if let ideal = metrics.distance.idealCarryYards {
                    metricsRow("Ideal Carry",
                               value: yards(ideal),
                               formula: "v²·sin(2θ)/g  (no drag, no lift)",
                               note: "correction factor: \(String(format: "%.2f", metrics.distance.carryCorrectionFactor))")
                }
                metricsRow("Carry", value: yards(metrics.distance.carryYards),
                           formula: "idealCarry × correctionFactor",
                           note: "tune correction factor slider for accuracy")
                if let rf = metrics.distance.rolloutFraction {
                    metricsRow("Rollout",
                               value: String(format: "%.0f%% of carry", rf * 100),
                               formula: "VLA bucket: \(metrics.distance.vlaBucket)", note: nil)
                }
                metricsRow("Rollout yards", value: yards(metrics.distance.rolloutYards),
                           formula: "carry × rolloutFraction", note: nil)
                metricsRow("Total", value: yards(metrics.distance.totalYards),
                           formula: "carry + rollout yards", note: "capped at 400 yd")
            }

            metricsGroup("Calibration") {
                let cal = metrics.calibration
                metricsRow("Image", value: "\(Int(cal.imageWidthPixels))×\(Int(cal.imageHeightPixels))", formula: nil, note: nil)
                metricsRow("H FOV", value: String(format: "%.1f°", cal.horizontalFOVDegrees), formula: nil, note: nil)
                metricsRow("V FOV", value: String(format: "%.1f°", cal.verticalFOVDegrees), formula: nil, note: nil)
                metricsRow("fx", value: String(format: "%.1f px", cal.focalLengthPixelsX), formula: "W / (2·tan(hFOV/2))", note: nil)
                metricsRow("fy", value: String(format: "%.1f px", cal.focalLengthPixelsY), formula: "H / (2·tan(vFOV/2))", note: nil)
                metricsRow("Ball Ø", value: String(format: "%.1f mm", cal.realBallDiameterMeters * 1000), formula: nil, note: nil)
                if let h = cal.cameraHeightMeters {
                    metricsRow("Cam height", value: String(format: "%.2f m", h), formula: nil, note: nil)
                }
                if let t = cal.cameraTiltDegrees {
                    metricsRow("Cam tilt", value: String(format: "%.1f°", t), formula: nil, note: nil)
                }
            }

            if !metrics.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WARNINGS").font(.system(size: 10, weight: .semibold)).foregroundColor(.yellow)
                    ForEach(metrics.warnings, id: \.self) { w in
                        HStack(alignment: .top, spacing: 6) {
                            Text("⚠").foregroundColor(.yellow)
                            Text(w).font(.system(size: 11)).foregroundColor(.yellow.opacity(0.85))
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func metricsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
            content()
        }
    }

    private func metricsRow(_ label: String, value: String, formula: String?, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(value).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.white)
            }
            if let formula {
                Text(formula).font(.system(size: 10, design: .monospaced)).foregroundColor(.cyan.opacity(0.75))
            }
            if let note {
                Text(note).font(.system(size: 10)).foregroundColor(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var metricsFormulas: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HOW METRICS ARE CALCULATED")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)

            formulaBlock("3D Position (pinhole model)",
                "Z = realBallDiameter × focalLength / apparentDiameterPixels\n" +
                "X = (px - cx) × Z / fx\n" +
                "Y = (py - cy) × Z / fy")

            formulaBlock("Ball Velocity",
                "Linear regression over ≥3 post-impact 3D positions vs time\n" +
                "2-point delta fallback if only 2 points available\n" +
                "speed = |velocity vector| in m/s → mph × 2.23694")

            formulaBlock("HLA (image-space reference-line)",
                "ref  = (cos θ, -sin θ)  in image coords (y-down)\n" +
                "perp = (sin θ, cos θ)\n" +
                "forward = v2d · ref\n" +
                "lateral = v2d · perp\n" +
                "HLA = atan2(lateral, forward)\n" +
                "0° when ball travels along reference line\n" +
                "θ = zeroDegreeAngleDeg (set in sidebar)")

            formulaBlock("HLA 3D raw (debug only)",
                "HLA_3D = atan2(vx, vz)  — may show ~90° if\n" +
                "depth estimate is off; use image-space HLA instead")

            formulaBlock("VLA",
                "VLA = atan2(vy, √(vx²+vz²))  — up/down angle")

            formulaBlock("Club Speed (frameDifference mode default)",
                "Club 3D position assumed at ball depth near impact\n" +
                "useFrameDifference=true detects motion between frames\n" +
                "Same linear fit / 2-point method as ball velocity")

            formulaBlock("Smash Factor",
                "smash = ball_speed_mph / club_speed_mph")

            formulaBlock("Distance — carry (physics model)",
                "idealCarry = v²·sin(2θ)/g  (pure ballistic, m)\n" +
                "carry = idealCarry × correctionFactor × 1.09361 yd/m\n" +
                "correctionFactor default 0.75 (tune with slider)\n" +
                "Accounts for drag; Magnus lift not modeled directly")

            formulaBlock("Distance — rollout/total",
                "rolloutFraction = f(VLA bucket) × speedAdjust\n" +
                "<1°:85%  1–3°:65%  3–6°:45%  6–10°:30%\n" +
                "10–15°:20%  15–22°:12%  22–30°:7%  ≥30°:3%\n" +
                "speedAdjust: <40mph×0.45  40–80×0.75  ≥130×1.1\n" +
                "rolloutYards = carry × rolloutFraction\n" +
                "total = carry + rolloutYards  (capped 400 yd)")

            formulaBlock("Estimated Spin (Model-Based)",
                "backspin = (800 + 90×speed + 120×VLA) × VLA_mult\n" +
                "VLA multiplier: <5°×0.60  5–10°×0.80  10–20°×1.00\n" +
                "  20–30°×1.20  ≥30°×1.35  clamp 300–9000 rpm\n" +
                "sidespin = (HLA − path) × 200 × (speed/100)\n" +
                "spinAxis = atan2(sidespin, backspin)\n" +
                "ESTIMATED — not measured")

            formulaBlock("Club Path & Face Angle (Estimated)",
                "Club path: image-space 2D linear fit of centroid\n" +
                "positions → projected onto 0° ref → atan2\n" +
                "Face angle: dominant edge direction via Sobel\n" +
                "gradient PCA on clubhead bounding box at impact\n" +
                "Face-to-path = face − club path\n" +
                "ESTIMATED — confidence varies with image quality")
        }
    }

    private func formulaBlock(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.85))
            Text(body).font(.system(size: 10, design: .monospaced)).foregroundColor(.cyan.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Impact info row

    private var impactInfoRow: some View {
        Group {
            if let r = result {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.yellow)
                    Text("Impact detected: frame \(r.detectedImpactFrameIndex)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white)
                    if r.detectedImpactFrameIndex != r.fallbackImpactFrameIndex {
                        Text("(fallback: \(r.fallbackImpactFrameIndex))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    Text(r.impactDetectionReason)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary).lineLimit(1)
                    Spacer()
                    if let c = r.initialBallCenter {
                        Text(String(format: "initCenter=(%.3f,%.3f)", c.x, c.y))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color(white: 0.08))
            } else {
                EmptyView()
            }
        }
    }

    private var metricsInfoRow: some View {
        Group {
            if let metrics = result?.metrics {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 12) {
                        metricCell("Ball Speed", value: mph(metrics.ballLaunch.ballSpeedMph))
                        metricCell("HLA (img-ref)", value: metrics.ballLaunch.hlaDisplay)
                        metricCell("VLA", value: degrees(metrics.ballLaunch.vlaDegrees))
                        metricCell("Club Speed", value: mph(metrics.club.clubSpeedMph))
                        metricCell("Smash", value: plain(metrics.smashFactor, digits: 2))
                        metricCell("Carry", value: yards(metrics.distance.carryYards))
                        metricCell("Total", value: yards(metrics.distance.totalYards))
                        metricCell("Backspin (Est)", value: metrics.spin.estimatedBackspinRpm.map { String(format: "%.0f rpm", $0) } ?? "—")
                        metricCell("Club Path (Est)", value: metrics.clubPath.clubPathDisplay)
                    }
                    HStack(spacing: 10) {
                        Text("ball pts \(metrics.ballLaunch.pointsUsed)")
                        Text("club pts \(metrics.club.pointsUsed)")
                        Text(String(format: "ball q %.2f", metrics.ballLaunch.quality))
                        Text(String(format: "club q %.2f", metrics.club.quality))
                        Text("impact \(metrics.detectedImpactFrameIndex)")
                        if let exportStatus {
                            Text(exportStatus)
                                .foregroundColor(.green)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if let warning = metrics.warnings.first {
                            Text(warning)
                                .foregroundColor(.yellow)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(white: 0.065))
            } else if result != nil {
                Text("Metrics: Not enough data")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(white: 0.065))
            } else {
                EmptyView()
            }
        }
    }

    private func metricCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Image pane

    private func imagePane(_ seq: BallTrackingTestSequence) -> some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if currentIndex < seq.frames.count,
                   let img = displayedImage(seq.frames[currentIndex]) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    let obs = result?.observations.first {
                        $0.frameIndex == seq.frames[currentIndex].frameIndex
                    }
                    let clubObs = result?.metrics?.clubObservations.first {
                        $0.frameIndex == seq.frames[currentIndex].frameIndex
                    }
                    let showCandBounds = settings.showOriginalCandidateBounds
                    Canvas { ctx, size in
                        drawOverlay(ctx: ctx, containerSize: size, image: img,
                                    obs: obs, metrics: result?.metrics,
                                    clubObs: clubObs,
                                    showCandidateBounds: showCandBounds)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)
                    infoOverlay(seq: seq, obs: obs, clubObs: clubObs)
                    if settings.showMaskPreview {
                        maskPreviewInset(obs)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, 8).padding(.trailing, 8)
                            .allowsHitTesting(false)
                    }
                } else {
                    Text("No image").foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func displayedImage(_ frame: BallTrackingTestFrame) -> UIImage? {
        displayMode == .original ? frame.image
            : normalizer.normalizedImage(from: frame.image, mode: displayMode)
    }

    // MARK: - Canvas overlay

    private func drawOverlay(ctx: GraphicsContext, containerSize: CGSize,
                              image: UIImage, obs: BallTrackingTestObservation?,
                              metrics: ExperimentalShotMetricsResult?,
                              clubObs: ExperimentalClubObservation?,
                              showCandidateBounds: Bool) {
        let dr = aspectFitRect(imageSize: image.size, in: containerSize)
        guard dr.width > 0, dr.height > 0 else { return }
        let dbg = obs?.frameDebug

        // Cyan dashed ROI
        if let roi = dbg?.searchROI {
            ctx.stroke(Path(normToView(roi, dr: dr)), with: .color(.cyan.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }

        // Rejected candidates — red dashed rects
        for cand in dbg?.candidates ?? [] where !cand.accepted {
            ctx.stroke(Path(normToView(cand.rect, dr: dr)), with: .color(.red.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }

        // Accepted-but-not-selected — yellow circles (candidate diameter)
        if let selected = dbg?.selectedCandidate {
            for cand in dbg?.candidates ?? [] where cand.accepted && cand.centerX != selected.centerX {
                strokeCircle(ctx: ctx, dr: dr, cx: cand.centerX, cy: cand.centerY,
                             d: cand.diameter, color: .yellow, lineWidth: 1.5)
            }
        }

        guard let cx = obs?.centerX, let cy = obs?.centerY else { return }

        // Optional faint gray dashed rect — selected candidate blob bbox
        if showCandidateBounds, let blobRect = dbg?.selectedCandidate?.rect {
            ctx.stroke(Path(normToView(blobRect, dr: dr)), with: .color(.white.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }

        // Green circle — tight around the white pixels in the B&W mask.
        if let maskRect = obs?.maskBoundsRect,
           let refinedD = obs?.maskRefinedDiameter {
            strokeCircle(ctx: ctx, dr: dr, cx: maskRect.midX, cy: maskRect.midY,
                         d: refinedD, color: .green, lineWidth: 2)
        } else if let finalD = obs?.diameter {
            strokeCircle(ctx: ctx, dr: dr, cx: cx, cy: cy,
                         d: finalD, color: .green, lineWidth: 2)
        }

        // Green center dot follows the refined mask center when available.
        let dotCenter = obs?.maskBoundsRect.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: cx, y: cy)
        let dotPx = CGPoint(x: dr.minX + dotCenter.x * dr.width, y: dr.minY + dotCenter.y * dr.height)
        ctx.fill(Path(ellipseIn: CGRect(x: dotPx.x - 2.5, y: dotPx.y - 2.5, width: 5, height: 5)),
                 with: .color(.green))

        if settings.showBallPath, let allObs = metrics?.ball3DObservations, allObs.count >= 2 {
            drawBallPath(ctx: ctx, dr: dr, observations: allObs,
                         zeroDeg: settings.zeroDegreeAngleDeg,
                         show0DegRef: settings.show0DegRef)
        } else if settings.show0DegRef, let firstObs = metrics?.ball3DObservations.first {
            // Draw 0° ref even without full ball path
            let origin = normPointToView(CGPoint(x: firstObs.imageX, y: firstObs.imageY), dr: dr)
            draw0DegRef(ctx: ctx, dr: dr, origin: origin, zeroDeg: settings.zeroDegreeAngleDeg)
        }

        if settings.club.showClubTracker {
            drawClubOverlay(ctx: ctx, dr: dr, metrics: metrics, clubObs: clubObs)
        }
    }

    private func drawBallPath(ctx: GraphicsContext, dr: CGRect,
                               observations: [ExperimentalBall3DObservation],
                               zeroDeg: Double, show0DegRef: Bool) {
        var path = Path()
        for (i, obs) in observations.enumerated() {
            let pt = normPointToView(CGPoint(x: obs.imageX, y: obs.imageY), dr: dr)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(.cyan.opacity(0.85)), style: StrokeStyle(lineWidth: 2, dash: [6, 3]))

        // Dots at each tracked point
        for obs in observations {
            let pt = normPointToView(CGPoint(x: obs.imageX, y: obs.imageY), dr: dr)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)),
                     with: .color(.cyan.opacity(0.65)))
        }

        if show0DegRef, let first = observations.first {
            let origin = normPointToView(CGPoint(x: first.imageX, y: first.imageY), dr: dr)
            draw0DegRef(ctx: ctx, dr: dr, origin: origin, zeroDeg: zeroDeg)
        }
    }

    /// Draws a dashed white 0° HLA reference line from `origin` in the given `zeroDeg` direction.
    private func draw0DegRef(ctx: GraphicsContext, dr: CGRect, origin: CGPoint, zeroDeg: Double) {
        let rad = zeroDeg * .pi / 180.0
        let len: CGFloat = min(dr.width, dr.height) * 0.32
        let end = CGPoint(x: origin.x + len * CGFloat(cos(rad)),
                          y: origin.y - len * CGFloat(sin(rad)))
        var refLine = Path()
        refLine.move(to: origin)
        refLine.addLine(to: end)
        ctx.stroke(refLine, with: .color(.white.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        // Label at line end
        let labelPt = CGPoint(x: end.x + 5, y: end.y - 7)
        ctx.draw(
            Text("0° HLA ref").font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.8)),
            at: labelPt, anchor: .leading
        )
    }

    private func drawClubOverlay(
        ctx: GraphicsContext,
        dr: CGRect,
        metrics: ExperimentalShotMetricsResult?,
        clubObs: ExperimentalClubObservation?
    ) {
        if settings.club.showClubPath,
           let pathObservations = metrics?.clubObservations.filter({ $0.isDetected }),
           pathObservations.count >= 2 {
            var path = Path()
            var started = false
            for obs in pathObservations {
                guard let x = obs.centerX, let y = obs.centerY else { continue }
                let point = normPointToView(CGPoint(x: x, y: y), dr: dr)
                if started { path.addLine(to: point) } else { path.move(to: point); started = true }
            }
            // Orange solid line through clubhead centers (smooth, no zig-zag)
            ctx.stroke(path, with: .color(.orange.opacity(0.85)), style: StrokeStyle(lineWidth: 2))
            for obs in pathObservations {
                guard let x = obs.centerX, let y = obs.centerY else { continue }
                let pt = normPointToView(CGPoint(x: x, y: y), dr: dr)
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)),
                         with: .color(.orange.opacity(0.65)))
            }
        }

        guard let clubObs else { return }

        if settings.club.showClubSearchROI, let roi = clubObs.searchROI {
            ctx.stroke(
                Path(normToView(roi, dr: dr)),
                with: .color(.orange.opacity(0.8)),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
        }

        if settings.club.showBallExclusionZone,
           let x = clubObs.ballExclusionCenterX,
           let y = clubObs.ballExclusionCenterY,
           let d = clubObs.ballExclusionDiameter {
            strokeCircle(ctx: ctx, dr: dr, cx: x, cy: y, d: d, color: .orange.opacity(0.32), lineWidth: 1)
        }

        if let bbox = clubObs.clubBoundingBox {
            ctx.stroke(Path(normToView(bbox, dr: dr)), with: .color(.orange.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 2))
        }

        if let cx = clubObs.centerX, let cy = clubObs.centerY {
            let point = normPointToView(CGPoint(x: cx, y: cy), dr: dr)
            ctx.fill(
                Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
                with: .color(.orange)
            )
        }

        if let lx = clubObs.leadingEdgeX, let ly = clubObs.leadingEdgeY {
            let point = normPointToView(CGPoint(x: lx, y: ly), dr: dr)
            let rect = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
            ctx.stroke(Path(ellipseIn: rect), with: .color(.purple), lineWidth: 2.5)
            ctx.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                     with: .color(.purple))
        }
    }

    private func strokeCircle(ctx: GraphicsContext, dr: CGRect,
                               cx: CGFloat, cy: CGFloat, d: CGFloat,
                               color: Color, lineWidth: CGFloat) {
        let radius = d * dr.width / 2
        let center = CGPoint(x: dr.minX + cx * dr.width, y: dr.minY + cy * dr.height)
        ctx.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2)),
                   with: .color(color), lineWidth: lineWidth)
    }

    private func normToView(_ rect: CGRect, dr: CGRect) -> CGRect {
        CGRect(x: dr.minX + rect.minX * dr.width, y: dr.minY + rect.minY * dr.height,
               width: rect.width * dr.width, height: rect.height * dr.height)
    }

    private func normPointToView(_ point: CGPoint, dr: CGRect) -> CGPoint {
        CGPoint(x: dr.minX + point.x * dr.width, y: dr.minY + point.y * dr.height)
    }

    // MARK: - Info overlay

    private func infoOverlay(seq: BallTrackingTestSequence,
                              obs: BallTrackingTestObservation?,
                              clubObs: ExperimentalClubObservation?) -> some View {
        let frame    = currentIndex < seq.frames.count ? seq.frames[currentIndex] : nil
        let detImpact = effectiveImpactIndex
        let isImpact  = frame?.frameIndex == detImpact
        let isPost    = (frame?.frameIndex ?? 0) > detImpact

        return VStack(alignment: .leading, spacing: 3) {
            // Line 1: frame + phase + time
            HStack(spacing: 8) {
                Text("Frame \(frame?.frameIndex ?? 0)").fontWeight(.semibold)
                Text(isImpact ? "IMPACT" : isPost ? "post" : "pre")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isImpact ? .red : isPost ? .orange : .secondary)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background((isImpact ? Color.red : isPost ? Color.orange : Color.secondary).opacity(0.2))
                    .clipShape(Capsule())
                if let t = frame?.relativeTime {
                    Text(String(format: "%+.1f ms", t * 1000)).foregroundColor(.secondary)
                }
            }
            // Line 2: center
            if let obs {
                if let cx = obs.centerX, let cy = obs.centerY {
                    Text(String(format: "x=%.4f  y=%.4f  conf=%.2f", cx, cy, obs.confidence))
                        .foregroundColor(.green)
                    // Line 3: diameter breakdown
                    let cD = obs.candidateDiameter.map   { String(format:"%.4f",$0) } ?? "—"
                    let rD = obs.maskRefinedDiameter.map { String(format:"%.4f",$0) } ?? "—"
                    let sD = obs.smoothedDiameter.map    { String(format:"%.4f",$0) } ?? "—"
                    Text("candidateD=\(cD)  refinedD=\(rD)  smoothedD=\(sD)  maskPx=\(obs.maskWhitePixelCount)")
                        .foregroundColor(.white.opacity(0.75))
                    Text("reason=\(obs.diameterDebugReason)")
                        .foregroundColor(.white.opacity(0.45))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                        Text(obs.debugReason).foregroundColor(.orange).lineLimit(1)
                    }
                }
                // Line 4: ROI debug
                if let dbg = obs.frameDebug {
                    Text("roi: \(dbg.searchCenterSource)  scale=\(String(format:"%.2f",dbg.searchScale))  cands=\(dbg.candidates.count)  acc=\(dbg.candidates.filter{$0.accepted}.count)")
                        .foregroundColor(.white.opacity(0.45))
                }

                if let clubObs {
                    if let lx = clubObs.leadingEdgeX, let ly = clubObs.leadingEdgeY {
                        Text(String(format: "club yes  lead=(%.4f,%.4f) conf=%.2f", lx, ly, clubObs.confidence))
                            .foregroundColor(.orange)
                    } else {
                        Text("club no  \(clubObs.debugReason)")
                            .foregroundColor(.orange.opacity(0.8))
                    }
                    if let roi = clubObs.searchROI {
                        Text(String(format: "clubROI=(%.3f,%.3f,%.3f,%.3f) diff=%@ excl=%@",
                                    roi.minX, roi.minY, roi.width, roi.height,
                                    clubObs.frameDifferenceWasUsed ? "yes" : "no",
                                    clubObs.ballExclusionWasApplied ? "yes" : "no"))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
            } else {
                Text(result == nil ? "Run tracker to see results" : "No observation")
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.white)
        .padding(8)
        .background(Color.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    // MARK: - Mask preview inset

    private func maskPreviewInset(_ obs: BallTrackingTestObservation?) -> some View {
        let sz: CGFloat = 160
        return VStack(spacing: 0) {
            // Header row with legend
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("old").font(.system(size: 8, design: .monospaced)).foregroundColor(.red.opacity(0.85))
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("new").font(.system(size: 8, design: .monospaced)).foregroundColor(.green.opacity(0.85))
                Spacer()
                Text("Mask Preview")
                    .font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.black.opacity(0.85))

            ZStack {
                Color.black
                if let img = obs?.maskPreviewImage {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: sz, height: sz)

                    Canvas { ctx, size in
                        let half = size.width / 2
                        // Red circle — original candidate diameter
                        if let candD = obs?.maskCandidateDiamInCrop {
                            let r = candD * size.width / 2
                            let c = CGPoint(x: half, y: size.height / 2)
                            ctx.stroke(
                                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                       width: r * 2, height: r * 2)),
                                with: .color(.red.opacity(0.9)), lineWidth: 1.5)
                        }
                        // Green circle — mask-refined diameter
                        if let refD = obs?.maskRefinedDiamInCrop {
                            let r = refD * size.width / 2
                            let c = refinedMaskCenterInCrop(obs, size: size) ?? CGPoint(x: half, y: size.height / 2)
                            ctx.stroke(
                                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                       width: r * 2, height: r * 2)),
                                with: .color(.green.opacity(0.9)), lineWidth: 1.5)
                        }
                        // Center dot
                        let c = refinedMaskCenterInCrop(obs, size: size) ?? CGPoint(x: half, y: size.height / 2)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)),
                                 with: .color(.yellow))
                    }
                    .frame(width: sz, height: sz)
                    .allowsHitTesting(false)
                } else {
                    let msg: String = {
                        if obs == nil            { return "no obs" }
                        if obs?.centerX == nil   { return "no ball" }
                        return "no mask"
                    }()
                    Text(msg)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: sz, height: sz)
                }
            }
            .frame(width: sz, height: sz)
        }
        .background(Color.black.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Frame strip

    private func frameStrip(_ seq: BallTrackingTestSequence) -> some View {
        let detImpact = effectiveImpactIndex
        let fallback  = result?.fallbackImpactFrameIndex ?? seq.impactFrameIndex
        let hasDiff   = result != nil && detImpact != fallback

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(seq.frames.enumerated()), id: \.offset) { i, frame in
                        let fi        = frame.frameIndex
                        let isCurrent = i == currentIndex
                        let isDetImp  = fi == detImpact
                        let isFallImp = hasDiff && fi == fallback
                        let obs = result?.observations.first { $0.frameIndex == fi }
                        let clubDetected = result?.metrics?.clubObservations.first {
                            $0.frameIndex == fi && $0.isDetected
                        } != nil

                        let blockColor: Color = isDetImp  ? .yellow
                            : isFallImp ? .yellow.opacity(0.35)
                            : obs?.centerX != nil ? .green
                            : result != nil ? .red
                            : Color(white: 0.25)

                        Button(action: { currentIndex = i }) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(blockColor.opacity(0.85))
                                .frame(width: 14, height: 28)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .stroke(Color.white, lineWidth: isCurrent ? 2 : 0)
                                )
                                .overlay(alignment: .bottom) {
                                    if clubDetected {
                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 5, height: 5)
                                            .padding(.bottom, 2)
                                    }
                                }
                        }
                        .id(i)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 40)
            .background(Color(white: 0.08))
            .onChange(of: currentIndex) { idx in
                withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(idx, anchor: .center) }
            }
        }
    }

    // MARK: - Navigation bar

    private func navigationBar(_ seq: BallTrackingTestSequence) -> some View {
        let last = max(0, seq.frames.count - 1)
        return HStack(spacing: 12) {
            Button(action: { if currentIndex > 0 { currentIndex -= 1 } }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(currentIndex > 0 ? .white : .white.opacity(0.25))
            }.frame(width: 44, height: 44)
            Slider(value: Binding(
                get: { Double(currentIndex) },
                set: { currentIndex = Int($0.rounded()) }
            ), in: 0...Double(last), step: 1).tint(.white)
            Button(action: { if currentIndex < last { currentIndex += 1 } }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(currentIndex < last ? .white : .white.opacity(0.25))
            }.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(white: 0.10))
    }

    // MARK: - Controls sidebar

    private var controlsSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                trackerModePicker

                TunerSection(title: "Global") {
                    TunerSlider(label: "sampleStride", value: $settings.sampleStride,
                                range: 1...8, format: "%.0f", isInt: true)
                }

                TunerSection(title: "Pre-impact") {
                    TunerSlider(label: "brightness ≥", value: $settings.preBrightnessThreshold,
                                range: 40...240, format: "%.0f", isInt: true)
                    TunerSlider(label: "spread ≤",     value: $settings.preMaxChannelSpread,
                                range: 10...180, format: "%.0f", isInt: true)
                    TunerSlider(label: "minSamples",   value: $settings.preMinBrightSamples,
                                range: 1...100, format: "%.0f", isInt: true)
                    TunerSlider(label: "minW",    value: $settings.preMinNormWidth,  range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "maxW",    value: $settings.preMaxNormWidth,  range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "minH",    value: $settings.preMinNormHeight, range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "maxH",    value: $settings.preMaxNormHeight, range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "minAspect", value: $settings.preMinAspect, range: 0.05...8.0, format: "%.2f")
                    TunerSlider(label: "maxAspect", value: $settings.preMaxAspect, range: 0.05...8.0, format: "%.2f")
                }

                TunerSection(title: "Post-impact") {
                    TunerSlider(label: "brightness ≥", value: $settings.postBrightnessThreshold,
                                range: 40...240, format: "%.0f", isInt: true)
                    TunerSlider(label: "spread ≤",     value: $settings.postMaxChannelSpread,
                                range: 10...180, format: "%.0f", isInt: true)
                    TunerSlider(label: "minSamples",   value: $settings.postMinBrightSamples,
                                range: 1...100, format: "%.0f", isInt: true)
                    TunerSlider(label: "minW",    value: $settings.postMinNormWidth,  range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "maxW",    value: $settings.postMaxNormWidth,  range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "minH",    value: $settings.postMinNormHeight, range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "maxH",    value: $settings.postMaxNormHeight, range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "minAspect", value: $settings.postMinAspect, range: 0.05...8.0, format: "%.2f")
                    TunerSlider(label: "maxAspect", value: $settings.postMaxAspect, range: 0.05...8.0, format: "%.2f")
                }

                TunerSection(title: "Search ROI") {
                    TunerSlider(label: "preScale",    value: $settings.preImpactSearchScale, range: 1...40, format: "%.2f")
                    TunerSlider(label: "impactScale", value: $settings.impactSearchScale,    range: 1...40, format: "%.2f")
                    TunerSlider(label: "postBase",    value: $settings.postImpactBaseScale,  range: 1...40, format: "%.2f")
                    TunerSlider(label: "postGrowth",  value: $settings.postImpactScaleGrowth,range: 0...5,  format: "%.2f")
                    TunerSlider(label: "postMax",     value: $settings.postImpactMaxScale,   range: 1...40, format: "%.1f")
                }

                TunerSection(title: "Calibration / 3D") {
                    TunerSlider(label: "horizontal FOV", value: $settings.calibration.horizontalFOVDegrees,
                                range: 35...110, format: "%.1f")
                    TunerSlider(label: "vertical FOV", value: $settings.calibration.verticalFOVDegrees,
                                range: 25...90, format: "%.1f")
                    TunerSlider(label: "ball diameter mm", value: Binding(
                        get: { settings.calibration.realBallDiameterMeters * 1000 },
                        set: { settings.calibration.realBallDiameterMeters = $0 / 1000 }
                    ), range: 35...50, format: "%.2f")
                    TunerToggle(label: "camera height", value: $settings.calibration.useCameraHeight)
                    TunerSlider(label: "height m", value: $settings.calibration.cameraHeightMeters,
                                range: 0...2.5, format: "%.2f")
                    TunerToggle(label: "camera tilt", value: $settings.calibration.useCameraTilt)
                    TunerSlider(label: "tilt deg", value: $settings.calibration.cameraTiltDegrees,
                                range: -45...45, format: "%.1f")
                    calibrationDerivedReadout
                    Button(action: { settings.calibration.resetDefaults() }) {
                        Text("Reset calibration defaults")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                }

                TunerSection(title: "Distance Model") {
                    TunerSlider(label: "carry correction",
                                value: $settings.carryCorrectionFactor,
                                range: 0.40...1.20, format: "%.2f")
                }

                TunerSection(title: "Impact Detection") {
                    TunerSlider(label: "moveThreshold",  value: $settings.impact.movementThresholdNorm,
                                range: 0.001...0.030, format: "%.3f")
                    TunerSlider(label: "confirmFrames",  value: $settings.impact.confirmFrames,
                                range: 1...5, format: "%.0f", isInt: true)
                    TunerSlider(label: "stableWindow",   value: $settings.impact.stableWindowCount,
                                range: 3...20, format: "%.0f", isInt: true)
                }

                TunerSection(title: "Diameter / Mask Refinement") {
                    TunerToggle(label: "enabled",          value: $settings.diameter.enabled)
                    TunerSlider(label: "maskWindowScale",  value: $settings.diameter.localMaskWindowScale,
                                range: 0.5...4.0, format: "%.2f")
                    TunerSlider(label: "minDiameter",      value: $settings.diameter.minDiameterNorm,
                                range: 0.001...0.10, format: "%.3f")
                    TunerSlider(label: "maxDiameter",      value: $settings.diameter.maxDiameterNorm,
                                range: 0.01...0.30, format: "%.3f")
                    TunerToggle(label: "combineMode=max",  value: $settings.diameter.combineModeIsMax)
                    TunerToggle(label: "smoothing",        value: $settings.diameter.smoothingEnabled)
                    TunerSlider(label: "medianWindow",     value: $settings.diameter.smoothingWindowSize,
                                range: 2...15, format: "%.0f", isInt: true)
                    TunerToggle(label: "show candidate rect", value: $settings.showOriginalCandidateBounds)
                    TunerToggle(label: "show mask preview",  value: $settings.showMaskPreview)
                    TunerToggle(label: "show ball path",     value: $settings.showBallPath)
                    TunerToggle(label: "show 0° ref line",   value: $settings.show0DegRef)
                    TunerSlider(label: "0° ref angle",       value: $settings.zeroDegreeAngleDeg,
                                range: -45...45, format: "%.1f")
                }

                TunerSection(title: "Club Tracking") {
                    TunerToggle(label: "enabled", value: $settings.club.enabled)
                    TunerToggle(label: "search behind ball", value: $settings.club.searchBehindBallEnabled)
                    TunerSlider(label: "ball exclusion x", value: $settings.club.ballExclusionRadiusScale,
                                range: 0.5...5.0, format: "%.2f")
                    TunerSlider(label: "roi scale X", value: $settings.club.clubSearchROIScaleX,
                                range: 1...16, format: "%.2f")
                    TunerSlider(label: "roi scale Y", value: $settings.club.clubSearchROIScaleY,
                                range: 1...12, format: "%.2f")
                    TunerToggle(label: "frame difference", value: $settings.club.useFrameDifference)
                    TunerSlider(label: "diff threshold", value: $settings.club.frameDifferenceThreshold,
                                range: 1...120, format: "%.0f", isInt: true)
                    TunerSlider(label: "dark/edge threshold", value: $settings.club.minClubDarknessOrEdgeThreshold,
                                range: 10...180, format: "%.0f", isInt: true)
                    TunerSlider(label: "min blob area", value: $settings.club.minClubBlobArea,
                                range: 1...300, format: "%.0f", isInt: true)
                    TunerSlider(label: "max blob area", value: $settings.club.maxClubBlobArea,
                                range: 100...20000, format: "%.0f", isInt: true)
                    TunerSlider(label: "min confidence", value: $settings.club.minClubConfidence,
                                range: 0...1, format: "%.2f")
                    TunerToggle(label: "debug logging", value: $settings.club.debugLoggingEnabled)
                    TunerToggle(label: "show club tracker", value: $settings.club.showClubTracker)
                    TunerToggle(label: "show club ROI", value: $settings.club.showClubSearchROI)
                    TunerToggle(label: "show club path", value: $settings.club.showClubPath)
                    TunerToggle(label: "show exclusion zone", value: $settings.club.showBallExclusionZone)
                    Button(action: { settings.club.resetDefaults() }) {
                        Text("Reset club defaults")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                }

                Button(action: { settings = BallTrackingTuningSettings() }) {
                    Text("Reset Defaults")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.orange)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 20)
        }
        .background(Color(white: 0.07))
    }

    private var trackerModePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TRACKER MODE")
                .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 12).padding(.top, 12)
            VStack(spacing: 1) {
                ForEach(FrameNormalizationMode.allCases, id: \.self) { mode in
                    Button(action: { settings.trackingMode = mode }) {
                        HStack {
                            Text(mode.displayName).font(.system(size: 12)).foregroundColor(.white)
                            Spacer()
                            if settings.trackingMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.purple)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(settings.trackingMode == mode ? Color.purple.opacity(0.15) : Color.clear)
                    }
                }
            }
            Divider().background(Color.white.opacity(0.1))
        }
    }

    private var calibrationDerivedReadout: some View {
        let width = sequence?.frames.first?.image.cgImage?.width ?? 0
        let height = sequence?.frames.first?.image.cgImage?.height ?? 0
        let calibration = ExperimentalCameraCalibration.from(
            settings: settings.calibration,
            imageWidth: width,
            imageHeight: height
        )
        return VStack(alignment: .leading, spacing: 3) {
            Text("image \(width)x\(height) px")
            Text(String(format: "fx=%.1f  fy=%.1f", calibration.focalLengthPixelsX, calibration.focalLengthPixelsY))
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(.white.opacity(0.55))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func loadExport(_ url: URL) {
        do {
            let seq = try loader.loadSequence(from: url)
            sequence = seq; currentIndex = seq.impactFrameIndex; result = nil; loadError = nil; exportStatus = nil
        } catch { loadError = error.localizedDescription }
    }

    private func runTracker() {
        guard let seq = sequence, !isRunning else { return }
        isRunning = true
        exportStatus = nil
        let cfg = settings.toConfiguration()
        let currentSettings = settings
        Task.detached(priority: .userInitiated) {
            let tracker = ExperimentalBallTracker(configuration: cfg)
            let r = tracker.run(on: seq)
            let metrics = ExperimentalShotMetricsCalculator().calculate(
                sequence: seq,
                ballResult: r,
                calibrationSettings: currentSettings.calibration,
                clubConfiguration: currentSettings.club.toConfig(
                    trackingMode: currentSettings.trackingMode,
                    sampleStride: currentSettings.sampleStride
                ),
                zeroDegreeAngleDegrees: currentSettings.zeroDegreeAngleDeg,
                carryCorrectionFactor: currentSettings.carryCorrectionFactor
            )
            if currentSettings.club.debugLoggingEnabled {
                print("Club overlay: Orange solid line = club center path")
            }
            let finalResult = BallTrackingTestResult(
                observations: r.observations,
                trackedCount: r.trackedCount,
                missingCount: r.missingCount,
                averageConfidence: r.averageConfidence,
                detectedImpactFrameIndex: r.detectedImpactFrameIndex,
                fallbackImpactFrameIndex: r.fallbackImpactFrameIndex,
                impactDetectionReason: r.impactDetectionReason,
                initialBallCenter: r.initialBallCenter,
                movementThresholdNorm: r.movementThresholdNorm,
                metrics: metrics
            )
            await MainActor.run { self.result = finalResult; self.isRunning = false }
        }
    }

    private func exportExperimentalMetrics() {
        guard let sequence, let result else { return }
        do {
            let url = try ExperimentalMetricsExporter().export(
                sequence: sequence,
                result: result,
                settings: settings
            )
            exportStatus = "exported \(url.lastPathComponent)"
        } catch {
            exportStatus = error.localizedDescription
        }
    }

    // MARK: - Geometry helpers

    private func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let scale = min(containerSize.width / imageSize.width,
                        containerSize.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (containerSize.width - w) / 2,
                      y: (containerSize.height - h) / 2, width: w, height: h)
    }

    private func frameCount(in url: URL) -> Int? {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return contents?.filter { $0.pathExtension == "png" }.count
    }

    private func refinedMaskCenterInCrop(_ obs: BallTrackingTestObservation?, size: CGSize) -> CGPoint? {
        guard let bounds = obs?.maskBoundsRect,
              let crop = obs?.maskCropNormRect,
              crop.width > 0,
              crop.height > 0 else {
            return nil
        }

        return CGPoint(
            x: ((bounds.midX - crop.minX) / crop.width) * size.width,
            y: ((bounds.midY - crop.minY) / crop.height) * size.height
        )
    }

    private func mph(_ value: Double?) -> String {
        value.map { String(format: "%.1f mph", $0) } ?? "—"
    }

    private func degrees(_ value: Double?) -> String {
        value.map { String(format: "%.1f°", $0) } ?? "—"
    }

    private func yards(_ value: Double?) -> String {
        value.map { String(format: "%.0f yd", $0) } ?? "—"
    }

    private func plain(_ value: Double?, digits: Int) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(digits)f", value)
    }
}

// MARK: - Reusable controls

private struct TunerSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
            content()
            Divider().background(Color.white.opacity(0.1)).padding(.top, 6)
        }
    }
}

private struct TunerSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var isInt: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(isInt ? "\(Int(value.rounded()))" : String(format: format, value))
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                    .frame(width: 52, alignment: .trailing)
            }
            Slider(value: $value, in: range).tint(.purple)
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
    }
}

private struct TunerToggle: View {
    let label: String
    @Binding var value: Bool
    var body: some View {
        HStack {
            Text(label).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.8))
            Spacer()
            Toggle("", isOn: $value).toggleStyle(.switch).scaleEffect(0.75, anchor: .trailing).labelsHidden()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

// MARK: - Keyboard navigation

private struct KeyboardNavigatorView: UIViewRepresentable {
    let onLeft:  () -> Void
    let onRight: () -> Void
    func makeUIView(context: Context) -> _KeyNavView {
        let v = _KeyNavView(); v.onLeft = onLeft; v.onRight = onRight; return v
    }
    func updateUIView(_ uiView: _KeyNavView, context: Context) {
        uiView.onLeft = onLeft; uiView.onRight = onRight
    }
    class _KeyNavView: UIView {
        var onLeft:  (() -> Void)?
        var onRight: (() -> Void)?
        override var canBecomeFirstResponder: Bool { true }
        override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { becomeFirstResponder() } }
        override var keyCommands: [UIKeyCommand]? {[
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow,  modifierFlags: [], action: #selector(handleLeft)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(handleRight))
        ]}
        @objc private func handleLeft()  { onLeft?() }
        @objc private func handleRight() { onRight?() }
    }
}
#endif
