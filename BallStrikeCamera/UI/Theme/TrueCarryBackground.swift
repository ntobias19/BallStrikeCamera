import SwiftUI

// MARK: - True Carry Background with topographic contour lines

struct TrueCarryBackground: View {
    var body: some View {
        ZStack {
            TCTheme.background.ignoresSafeArea()
            TopoLinesCanvas()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

private struct TopoLinesCanvas: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                drawTopoLines(ctx: ctx, size: size)
            }
        }
    }

    private func drawTopoLines(ctx: GraphicsContext, size: CGSize) {
        let lineColor = Color.white.opacity(0.028)
        let lineWidth: CGFloat = 0.8

        // Gentle curved contour lines suggesting terrain
        let curves: [(startX: CGFloat, startY: CGFloat, cp1X: CGFloat, cp1Y: CGFloat, cp2X: CGFloat, cp2Y: CGFloat, endX: CGFloat, endY: CGFloat)] = [
            (0, size.height * 0.18, size.width * 0.35, size.height * 0.10, size.width * 0.65, size.height * 0.26, size.width, size.height * 0.15),
            (0, size.height * 0.32, size.width * 0.40, size.height * 0.24, size.width * 0.60, size.height * 0.40, size.width, size.height * 0.30),
            (0, size.height * 0.50, size.width * 0.30, size.height * 0.42, size.width * 0.70, size.height * 0.56, size.width, size.height * 0.48),
            (0, size.height * 0.66, size.width * 0.45, size.height * 0.58, size.width * 0.55, size.height * 0.72, size.width, size.height * 0.64),
            (0, size.height * 0.80, size.width * 0.38, size.height * 0.74, size.width * 0.62, size.height * 0.86, size.width, size.height * 0.78),
        ]

        for c in curves {
            var path = Path()
            path.move(to: CGPoint(x: c.startX, y: c.startY))
            path.addCurve(
                to: CGPoint(x: c.endX, y: c.endY),
                control1: CGPoint(x: c.cp1X, y: c.cp1Y),
                control2: CGPoint(x: c.cp2X, y: c.cp2Y)
            )
            ctx.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
        }

        // Subtle dot grid
        let dotColor = Color.white.opacity(0.018)
        let spacing: CGFloat = 44
        var x: CGFloat = spacing
        while x < size.width {
            var y: CGFloat = spacing
            while y < size.height {
                let dot = Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                ctx.fill(dot, with: .color(dotColor))
                y += spacing
            }
            x += spacing
        }
    }
}

// MARK: - True Carry Logo

struct TrueCarryLogo: View {
    var size: CGFloat = 28
    var showWordmark: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            logoMark
            if showWordmark {
                Text("TRUE CARRY")
                    .font(.system(size: size * 0.50, weight: .black, design: .default))
                    .tracking(2.0)
                    .foregroundColor(TCTheme.textPrimary)
            }
        }
    }

    private var logoMark: some View {
        ZStack {
            Circle()
                .fill(TCTheme.goldGradient)
                .frame(width: size, height: size)
            Image(systemName: "flag.fill")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundColor(.black)
        }
    }
}
