import SwiftUI

// Side-view ball flight animation: launches from ground at VLA, arcs through air to carry,
// then rolls along ground to total. Two distinct phases, two distinct colors.
struct CinematicBallFlightView: View {

    var carryYards:   Double?
    var totalYards:   Double?
    var ballSpeedMph: Double?
    var vlaDegrees:   Double?
    var onComplete:   (() -> Void)? = nil

    // Phase 1: airborne arc (0 → 1 as ball travels from tee to carry)
    @State private var flightProgress:  CGFloat = 0
    // Phase 2: ground roll (0 → 1 as ball rolls from carry to total)
    @State private var rolloutProgress: CGFloat = 0
    @State private var showCarryMarker: Bool    = false
    @State private var showTotalMarker: Bool    = false

    static let airborneColor = Color(red: 0.0,  green: 0.85, blue: 1.0)   // electric cyan
    static let rolloutColor  = Color(red: 1.0,  green: 0.60, blue: 0.10)  // orange
    static let totalColor    = Color(red: 0.30, green: 0.95, blue: 0.45)  // green

    // MARK: - Durations

    private var animDurations: (flight: Double, rollout: Double) {
        guard let spd = ballSpeedMph, let vla = vlaDegrees, spd > 0, vla > 0 else {
            return (2.2, 0.8)
        }
        let speedMps = spd * 0.44704
        let vlaRad   = vla * .pi / 180.0
        let vertVel  = speedMps * sin(vlaRad)
        let hangTime = max(0.8, min(7.0, 2.0 * vertVel / 9.81))
        let flt      = min(max(hangTime * 0.65, 1.4), 4.0)

        let carryYd  = carryYards ?? 0
        let totalYd  = totalYards ?? carryYd
        let rollYd   = max(0, totalYd - carryYd)
        let roll     = min(max(rollYd / 25.0, 0.4), 2.0)
        return (flt, roll)
    }

    // MARK: - Parabola

    // Physical peak height (yards) from ball speed + VLA
    private var peakHeightYards: Double {
        guard let spd = ballSpeedMph, let vla = vlaDegrees, spd > 0, vla > 0 else {
            return (carryYards ?? 100) * 0.12
        }
        let speedMps = spd * 0.44704
        let vlaRad   = vla * .pi / 180.0
        let vertVel  = speedMps * sin(vlaRad)
        let peakM    = (vertVel * vertVel) / (2.0 * 9.81)
        return max(peakM * 1.09361, 4.0)   // metres → yards
    }

    // Parabolic height at downrange x, for a ball that carries `carry` yards
    private func arcH(x: Double, carry: Double, peak: Double) -> Double {
        guard carry > 0 else { return 0 }
        return (4.0 * peak / (carry * carry)) * x * (carry - x)
    }

    // MARK: - Body

    var body: some View {
        Canvas { ctx, size in
            drawScene(ctx: ctx, size: size)
        }
        .background(Color(white: 0.06))
        .onAppear { startAnimation() }
    }

    // MARK: - Scene drawing

    private func drawScene(ctx: GraphicsContext, size: CGSize) {
        let totalYd  = totalYards  ?? carryYards ?? 100
        let carryYd  = carryYards  ?? totalYd
        let rollYd   = max(0, totalYd - carryYd)
        let peakYd   = peakHeightYards

        // Layout
        let groundY: CGFloat = size.height * 0.78
        let leftPad: CGFloat = 52
        let rightPad: CGFloat = 14
        let topPad: CGFloat  = 22

        let xRange = totalYd * 1.06       // 6% right padding
        let yRange = max(peakYd * 1.12, 6.0)  // 12% top headroom

        let plotW = size.width - leftPad - rightPad
        let plotH = groundY - topPad

        func sx(_ yd: Double) -> CGFloat { leftPad + CGFloat(yd / xRange) * plotW }
        func sy(_ yd: Double) -> CGFloat { groundY - CGFloat(yd / yRange) * plotH }

        let teeX   = sx(0)
        let carryX = sx(carryYd)
        let totalX = sx(totalYd)

        // --- Ground ---
        var ground = Path()
        ground.move(to: CGPoint(x: 0,          y: groundY))
        ground.addLine(to: CGPoint(x: size.width, y: groundY))
        ctx.stroke(ground, with: .color(Color.white.opacity(0.28)), lineWidth: 1.5)

        // Distance tick marks
        let stepYd: Double = totalYd <= 75 ? 25 : (totalYd <= 150 ? 50 : 100)
        var tickYd = stepYd
        while tickYd < totalYd {
            let tx = sx(tickYd)
            var tick = Path()
            tick.move(to: CGPoint(x: tx, y: groundY - 4))
            tick.addLine(to: CGPoint(x: tx, y: groundY + 4))
            ctx.stroke(tick, with: .color(Color.white.opacity(0.18)), lineWidth: 1)
            let lbl = Text("\(Int(tickYd))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.22))
            ctx.draw(lbl, at: CGPoint(x: tx, y: groundY + 14), anchor: .center)
            tickYd += stepYd
        }

        // Vertical height axis (left side)
        var yAxis = Path()
        yAxis.move(to: CGPoint(x: teeX, y: topPad))
        yAxis.addLine(to: CGPoint(x: teeX, y: groundY))
        ctx.stroke(yAxis, with: .color(Color.white.opacity(0.08)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 6]))

        // Height label at peak (right of axis)
        let peakScreenY = sy(peakYd)
        let pkLbl = Text(String(format: "%.0f yd", peakYd))
            .font(.system(size: 8, design: .monospaced))
            .foregroundColor(Color.white.opacity(0.20))
        ctx.draw(pkLbl, at: CGPoint(x: teeX - 4, y: peakScreenY), anchor: .trailing)

        // Tee peg
        var tee = Path()
        tee.move(to: CGPoint(x: teeX - 6, y: groundY - 8))
        tee.addLine(to: CGPoint(x: teeX + 6, y: groundY - 8))
        tee.move(to: CGPoint(x: teeX, y: groundY - 8))
        tee.addLine(to: CGPoint(x: teeX, y: groundY))
        ctx.stroke(tee, with: .color(Color.white.opacity(0.65)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // --- Airborne arc (flight phase) ---
        if flightProgress > 0 {
            let sampledCarry = carryYd * Double(flightProgress)
            let steps = 80
            let stepSize = sampledCarry / Double(steps)
            var arcPath = Path()
            var first = true
            var xi = 0.0
            while xi <= sampledCarry + stepSize * 0.5 {
                let h  = arcH(x: xi, carry: carryYd, peak: peakYd)
                let pt = CGPoint(x: sx(xi), y: sy(h))
                if first { arcPath.move(to: pt); first = false } else { arcPath.addLine(to: pt) }
                xi += max(stepSize, 0.01)
            }
            ctx.stroke(arcPath, with: .color(Self.airborneColor),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }

        // --- Rollout segment (ground phase) ---
        if rolloutProgress > 0 && rollYd > 0.2 {
            let rolledX = sx(carryYd + rollYd * Double(rolloutProgress))
            var rollPath = Path()
            rollPath.move(to: CGPoint(x: carryX, y: groundY - 1))
            rollPath.addLine(to: CGPoint(x: rolledX, y: groundY - 1))
            ctx.stroke(rollPath, with: .color(Self.rolloutColor),
                       style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
        }

        // --- Ball dot ---
        let ballPos: CGPoint?
        let ballColor: Color
        if rolloutProgress > 0.005 && rollYd > 0.2 {
            let rolledYd = carryYd + rollYd * Double(rolloutProgress)
            ballPos   = CGPoint(x: sx(rolledYd), y: groundY - 1)
            ballColor = Self.rolloutColor
        } else if flightProgress > 0.005 && flightProgress < 0.998 {
            let xi = carryYd * Double(flightProgress)
            let h  = arcH(x: xi, carry: carryYd, peak: peakYd)
            ballPos   = CGPoint(x: sx(xi), y: sy(h))
            ballColor = Self.airborneColor
        } else {
            ballPos = nil; ballColor = .white
        }

        if let bp = ballPos, !(showTotalMarker && rolloutProgress > 0.995) {
            let r: CGFloat = 9
            ctx.fill(Path(ellipseIn: CGRect(x: bp.x-r*2.3, y: bp.y-r*2.3, width: r*4.6, height: r*4.6)),
                     with: .color(ballColor.opacity(0.18)))
            ctx.fill(Path(ellipseIn: CGRect(x: bp.x-r, y: bp.y-r, width: r*2, height: r*2)),
                     with: .color(Color.white))
            ctx.fill(Path(ellipseIn: CGRect(x: bp.x-r*0.38, y: bp.y-r*0.38, width: r*0.76, height: r*0.76)),
                     with: .color(ballColor))
        }

        // --- Carry marker ---
        if showCarryMarker {
            // Vertical dashed drop line
            var drop = Path()
            drop.move(to: CGPoint(x: carryX, y: sy(peakYd * 0.15)))
            drop.addLine(to: CGPoint(x: carryX, y: groundY))
            ctx.stroke(drop, with: .color(Self.airborneColor.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

            // Dot
            ctx.fill(Path(ellipseIn: CGRect(x: carryX-5, y: groundY-5, width: 10, height: 10)),
                     with: .color(Self.airborneColor))

            // "Carry N yd" label
            let lbl = Text(String(format: "Carry  %.0f yd", carryYd))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Self.airborneColor)
            ctx.draw(lbl, at: CGPoint(x: carryX, y: groundY + 26), anchor: .center)
        }

        // --- Total marker ---
        if showTotalMarker {
            ctx.fill(Path(ellipseIn: CGRect(x: totalX-7, y: groundY-7, width: 14, height: 14)),
                     with: .color(Self.totalColor))

            let totalLbl = Text(String(format: "Total  %.0f yd", totalYd))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Self.totalColor)
            ctx.draw(totalLbl, at: CGPoint(x: totalX, y: groundY + 44), anchor: .center)

            if rollYd > 0.5 {
                let rollLbl = Text(String(format: "Rollout  %.0f yd", rollYd))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Self.rolloutColor.opacity(0.85))
                ctx.draw(rollLbl, at: CGPoint(x: totalX, y: groundY + 58), anchor: .center)
            }
        }

        // --- VLA angle label near tee ---
        if let vla = vlaDegrees {
            let vlaRad  = CGFloat(vla * .pi / 180.0)
            let arcR: CGFloat = 38
            let arcPath = Path { p in
                p.addArc(center: CGPoint(x: teeX, y: groundY),
                         radius: arcR, startAngle: .degrees(0),
                         endAngle: .degrees(-vla), clockwise: true)
            }
            ctx.stroke(arcPath, with: .color(Self.rolloutColor.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
            let midRad = CGFloat(vla / 2 * .pi / 180.0)
            let lblPt  = CGPoint(x: teeX + (arcR + 16) * cos(midRad),
                                 y: groundY - (arcR + 16) * sin(midRad))
            let vlaLbl = Text(String(format: "%.1f°", vla))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Self.rolloutColor.opacity(0.80))
            ctx.draw(vlaLbl, at: lblPt, anchor: .center)
        }
    }

    // MARK: - Animation

    func startAnimation() {
        let (flightDur, rolloutDur) = animDurations
        flightProgress  = 0
        rolloutProgress = 0
        showCarryMarker = false
        showTotalMarker = false

        withAnimation(.easeOut(duration: flightDur)) {
            flightProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + flightDur) {
            showCarryMarker = true

            let rollYd = max(0, (totalYards ?? 0) - (carryYards ?? 0))
            if rollYd > 0.2 {
                withAnimation(.easeIn(duration: rolloutDur)) {
                    rolloutProgress = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + rolloutDur) {
                    showTotalMarker = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        onComplete?()
                    }
                }
            } else {
                showTotalMarker = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    onComplete?()
                }
            }
        }
    }
}
