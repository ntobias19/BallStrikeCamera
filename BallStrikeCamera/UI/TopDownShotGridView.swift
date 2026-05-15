import SwiftUI

struct TopDownShotGridView: View {
    var carryYards: Double?
    var totalYards: Double?
    var hlaDegrees: Double?
    var sidespinRpmSigned: Double?
    var spinAxisDegreesSigned: Double?

    @State private var ballProgress: CGFloat = 0

    // Electric cyan for flight path
    private static let pathColor = Color(red: 0.0, green: 0.88, blue: 1.0)

    var body: some View {
        ZStack {
            Color(white: 0.06)
            Canvas { ctx, size in
                let layout = Layout(size: size)
                let geo    = buildGeometry()
                logScale(geo: geo)
                drawGrid(ctx: ctx, layout: layout, geo: geo)
                drawTargetLine(ctx: ctx, layout: layout, geo: geo)
                drawPath(ctx: ctx, layout: layout, geo: geo)
                drawMarkers(ctx: ctx, layout: layout, geo: geo)
                drawBall(ctx: ctx, layout: layout, geo: geo)
                drawLabels(ctx: ctx, layout: layout, geo: geo)
            }
        }
        .onAppear { animateIn() }
    }

    // MARK: - Layout

    private struct Layout {
        let size: CGSize
        let padTop:    CGFloat = 20
        let padBottom: CGFloat = 50
        let padH:      CGFloat = 46
        var plotW:  CGFloat { size.width - padH * 2 }
        var plotH:  CGFloat { size.height - padTop - padBottom }
        var originX: CGFloat { size.width / 2 }
        var originY: CGFloat { size.height - padBottom }
    }

    // MARK: - Geometry

    private struct ShotGeometry {
        let maxDownYd:     Double
        let maxOfflineYd:  Double  // half-axis (symmetric ±)
        let totalOff:      Double  // signed offline of landing
        let carryOff:      Double  // signed offline of carry
        let totalYd:       Double
        let carryYd:       Double
        let curveOffset:   Double  // lateral bulge at mid-path (positive=right)
    }

    private func buildGeometry() -> ShotGeometry {
        let totalYd = totalYards ?? carryYards ?? 0
        let carryYd = carryYards ?? totalYd
        let hlaRad  = (hlaDegrees ?? 0) * .pi / 180.0
        let totalOff = tan(hlaRad) * totalYd
        let carryOff = tan(hlaRad) * carryYd

        // Curve from spin axis (preferred) or sidespin
        let curveStrength: Double
        if let sa = spinAxisDegreesSigned, abs(sa) > 0.5 {
            let sign: Double = sa > 0 ? 1 : -1
            curveStrength = sign * min(abs(sa) / 16.0, 1.0)
        } else if let ss = sidespinRpmSigned, abs(ss) > 30 {
            let sign: Double = ss > 0 ? 1 : -1
            curveStrength = sign * min(abs(ss) / 1100.0, 1.0)
        } else {
            curveStrength = 0
        }
        let curveOffset = curveStrength * max(totalYd * 0.13, 6)

        // Tight horizontal scale: based on MAX of offline endpoints, not their sum
        let neededOff = max(abs(totalOff), abs(carryOff), abs(curveOffset))
        let maxOfflineYd: Double
        if      neededOff <= 10 { maxOfflineYd = 20 }
        else if neededOff <= 20 { maxOfflineYd = 30 }
        else if neededOff <= 30 { maxOfflineYd = 40 }
        else if neededOff <= 45 { maxOfflineYd = 55 }
        else                    { maxOfflineYd = ceil((neededOff + 15) / 10) * 10 }

        let downSteps: [Double] = [50, 100, 150, 200, 250, 300, 350, 400]
        let maxDownYd = downSteps.first { $0 >= totalYd * 1.08 } ?? 400

        return ShotGeometry(maxDownYd: maxDownYd, maxOfflineYd: maxOfflineYd,
                            totalOff: totalOff, carryOff: carryOff,
                            totalYd: totalYd, carryYd: carryYd, curveOffset: curveOffset)
    }

    private func logScale(geo: ShotGeometry) {
        print(String(format: "[TopDownGrid] vertMax=%.0f  horizMax=±%.0f  offline=%.1f  curve=%.1f  spinAxis=%.1f  sidespin=%.0f",
                     geo.maxDownYd, geo.maxOfflineYd, geo.totalOff, geo.curveOffset,
                     spinAxisDegreesSigned ?? 0, sidespinRpmSigned ?? 0))
    }

    // MARK: - Coordinate mapping

    private func pt(off: Double, down: Double, layout: Layout, geo: ShotGeometry) -> CGPoint {
        CGPoint(
            x: layout.originX + CGFloat(off / geo.maxOfflineYd) * (layout.plotW / 2),
            y: layout.originY - CGFloat(down / geo.maxDownYd)   *  layout.plotH
        )
    }

    // MARK: - Bezier helpers

    private func controlPoints(layout: Layout, geo: ShotGeometry) -> (p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint) {
        let p0 = pt(off: 0,             down: 0,            layout: layout, geo: geo)
        let p3 = pt(off: geo.totalOff,  down: geo.totalYd,  layout: layout, geo: geo)

        // ctrl1: along initial HLA direction at 35% downrange
        let c1 = pt(off: geo.totalOff * 0.35,
                    down: geo.totalYd * 0.35, layout: layout, geo: geo)

        // ctrl2: at 70% downrange, shifted by curve bulge
        let c2 = pt(off: geo.totalOff * 0.70 + geo.curveOffset,
                    down: geo.totalYd * 0.70, layout: layout, geo: geo)

        return (p0, c1, c2, p3)
    }

    private func sampleCubic(t: CGFloat, p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*p3.x,
            y: u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*p3.y
        )
    }

    // MARK: - Grid

    private func drawGrid(ctx: GraphicsContext, layout: Layout, geo: ShotGeometry) {
        ctx.fill(Path(CGRect(origin: .zero, size: layout.size)), with: .color(Color(white: 0.06)))

        let gridC = Color.white.opacity(0.08)
        let dashStyle = StrokeStyle(lineWidth: 0.5, dash: [3, 5])
        let lblColor  = Color.white.opacity(0.28)

        // Downrange horizontal lines
        let downStep: Double = geo.maxDownYd <= 100 ? 25 : (geo.maxDownYd <= 200 ? 50 : 100)
        var yd = downStep
        while yd <= geo.maxDownYd {
            let y = layout.originY - CGFloat(yd / geo.maxDownYd) * layout.plotH
            var p = Path()
            p.move(to: CGPoint(x: layout.padH * 0.30, y: y))
            p.addLine(to: CGPoint(x: layout.size.width - layout.padH * 0.30, y: y))
            ctx.stroke(p, with: .color(gridC), style: dashStyle)

            let lbl = Text("\(Int(yd))")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(lblColor)
            ctx.draw(lbl, at: CGPoint(x: layout.padH * 0.16 + 4, y: y), anchor: .leading)
            yd += downStep
        }

        // Lateral vertical lines
        let offStep: Double = geo.maxOfflineYd <= 25 ? 10 : (geo.maxOfflineYd <= 50 ? 15 : 25)
        var off = offStep
        while off < geo.maxOfflineYd {
            for sign in [-1.0, 1.0] {
                let x = layout.originX + CGFloat(off * sign / geo.maxOfflineYd) * (layout.plotW / 2)
                var p = Path()
                p.move(to: CGPoint(x: x, y: layout.padTop))
                p.addLine(to: CGPoint(x: x, y: layout.originY))
                ctx.stroke(p, with: .color(gridC), style: dashStyle)

                let anchor: UnitPoint = sign > 0 ? .trailing : .leading
                let lbl = Text("\(Int(off))")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(lblColor)
                ctx.draw(lbl, at: CGPoint(x: x + CGFloat(sign)*3, y: layout.originY + 12), anchor: anchor)
            }
            off += offStep
        }
    }

    private func drawTargetLine(ctx: GraphicsContext, layout: Layout, geo: ShotGeometry) {
        let origin = pt(off: 0, down: 0, layout: layout, geo: geo)
        var p = Path()
        p.move(to: origin)
        p.addLine(to: CGPoint(x: origin.x, y: layout.padTop))
        ctx.stroke(p, with: .color(Color.white.opacity(0.18)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [5, 7]))
        let lbl = Text("Target")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.35))
        ctx.draw(lbl, at: CGPoint(x: origin.x + 5, y: layout.padTop + 8), anchor: .leading)
    }

    // MARK: - Shot path

    private func drawPath(ctx: GraphicsContext, layout: Layout, geo: ShotGeometry) {
        guard geo.totalYd > 0 else {
            let lbl = Text("Distance unavailable")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.40))
            ctx.draw(lbl, at: CGPoint(x: layout.size.width/2, y: layout.size.height/2), anchor: .center)
            return
        }

        let (p0, c1, c2, p3) = controlPoints(layout: layout, geo: geo)

        // Faint full guide
        var guide = Path()
        guide.move(to: p0)
        guide.addCurve(to: p3, control1: c1, control2: c2)
        ctx.stroke(guide, with: .color(Color.white.opacity(0.10)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))

        // Animated leading path
        guard ballProgress > 0 else { return }
        let steps = 80
        let maxStep = Int(CGFloat(steps) * ballProgress)
        guard maxStep >= 1 else { return }

        var animPath = Path()
        animPath.move(to: p0)
        for i in 1...maxStep {
            let t = CGFloat(i) / CGFloat(steps)
            animPath.addLine(to: sampleCubic(t: t, p0: p0, c1: c1, c2: c2, p3: p3))
        }
        ctx.stroke(animPath, with: .color(Self.pathColor),
                   style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Markers

    private func drawMarkers(ctx: GraphicsContext, layout: Layout, geo: ShotGeometry) {
        guard geo.totalYd > 0 else { return }
        let (p0, c1, c2, p3) = controlPoints(layout: layout, geo: geo)

        // Tee
        filledDot(ctx: ctx, at: p0, r: 6, color: .white)

        // Carry marker
        let carryT = geo.totalYd > 0 ? CGFloat(geo.carryYd / geo.totalYd) : 0
        if carryYards != nil && geo.carryYd < geo.totalYd * 0.97 && ballProgress >= carryT {
            let carryPt = sampleCubic(t: carryT, p0: p0, c1: c1, c2: c2, p3: p3)
            filledDot(ctx: ctx, at: carryPt, r: 5, color: Color(red: 1.0, green: 0.65, blue: 0.0))
        }

        // Landing marker
        if ballProgress >= 0.97 {
            filledDot(ctx: ctx, at: p3, r: 7, color: Color(red: 0.3, green: 0.95, blue: 0.45))
            // Offline drop-line to baseline
            var drop = Path()
            drop.move(to: p3)
            drop.addLine(to: CGPoint(x: p3.x, y: p0.y))
            ctx.stroke(drop, with: .color(Color.white.opacity(0.15)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
        }
    }

    // MARK: - Animated ball dot

    private func drawBall(ctx: GraphicsContext, layout: Layout, geo: ShotGeometry) {
        guard geo.totalYd > 0, ballProgress > 0.01, ballProgress < 0.97 else { return }
        let (p0, c1, c2, p3) = controlPoints(layout: layout, geo: geo)
        let pos = sampleCubic(t: ballProgress, p0: p0, c1: c1, c2: c2, p3: p3)
        let r: CGFloat = 8
        // Glow
        ctx.fill(Path(ellipseIn: CGRect(x: pos.x-r*2, y: pos.y-r*2, width: r*4, height: r*4)),
                 with: .color(Self.pathColor.opacity(0.22)))
        // Ball
        ctx.fill(Path(ellipseIn: CGRect(x: pos.x-r, y: pos.y-r, width: r*2, height: r*2)),
                 with: .color(Color.white))
    }

    // MARK: - Labels

    private func drawLabels(ctx: GraphicsContext, layout: Layout, geo: ShotGeometry) {
        guard geo.totalYd > 0, ballProgress >= 0.97 else { return }
        let (_, _, _, p3) = controlPoints(layout: layout, geo: geo)

        let y0 = layout.size.height - layout.padBottom + 9

        // Left: Total / Carry
        var lx = layout.padH * 0.25
        let totalTxt  = Text(String(format: "Total  %.0f yd", geo.totalYd))
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(Color(red: 0.3, green: 0.95, blue: 0.45))
        ctx.draw(totalTxt, at: CGPoint(x: lx, y: y0), anchor: .leading)

        if carryYards != nil && geo.carryYd < geo.totalYd * 0.97 {
            let carryTxt = Text(String(format: "Carry  %.0f yd", geo.carryYd))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(red: 1.0, green: 0.65, blue: 0.0))
            ctx.draw(carryTxt, at: CGPoint(x: lx, y: y0 + 14), anchor: .leading)
        }

        // Right: Offline / HLA
        lx = layout.size.width / 2 + 6
        let absOff = abs(geo.totalOff)
        if absOff >= 0.5 {
            let side = geo.totalOff > 0 ? "R" : "L"
            let offTxt = Text(String(format: "Offline  %.0f yd %@", absOff, side))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.65))
            ctx.draw(offTxt, at: CGPoint(x: lx, y: y0), anchor: .leading)
        }
        if let hla = hlaDegrees, abs(hla) >= 0.1 {
            let side = hla > 0 ? "R" : "L"
            let hlaTxt = Text(String(format: "HLA  %.1f° %@", abs(hla), side))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.55))
            ctx.draw(hlaTxt, at: CGPoint(x: lx, y: y0 + 14), anchor: .leading)
        }

        // Scale indicator
        let scaleTxt = Text(String(format: "±%.0f yd", geo.maxOfflineYd))
            .font(.system(size: 8, weight: .regular, design: .monospaced))
            .foregroundColor(Color.white.opacity(0.25))
        ctx.draw(scaleTxt, at: CGPoint(x: layout.size.width - 6, y: layout.padTop + 4), anchor: .trailing)

        // Label near landing dot
        let dotLbl = Text(String(format: "%.0f yd", geo.totalYd))
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(Color(red: 0.3, green: 0.95, blue: 0.45))
        let lblPt = CGPoint(x: p3.x + 10, y: p3.y - 2)
        ctx.draw(dotLbl, at: lblPt, anchor: .leading)
    }

    // MARK: - Helpers

    private func filledDot(ctx: GraphicsContext, at pt: CGPoint, r: CGFloat, color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: pt.x-r, y: pt.y-r, width: r*2, height: r*2)),
                 with: .color(color))
    }

    // MARK: - Animation

    func animateIn() {
        ballProgress = 0
        withAnimation(.easeInOut(duration: 1.7)) { ballProgress = 1 }
    }
}
