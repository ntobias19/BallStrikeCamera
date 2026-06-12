import SwiftUI
import CoreImage.CIFilterBuiltins

/// Displays the 6-digit session code, QR code, and live status for the browser sim.
struct LiveSimCodeView: View {
    @ObservedObject var liveSimService: LiveSimService
    let onStartCamera: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Live Sim Session")

            VStack(spacing: 20) {
                // Code + QR side by side
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SESSION CODE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(BSTheme.textMuted)
                            .kerning(1.2)

                        Text(liveSimService.sessionCode)
                            .font(.system(size: 38, weight: .bold, design: .monospaced))
                            .foregroundColor(BSTheme.electricCyan)
                            .minimumScaleFactor(0.7)

                        Text("Open truecarry.app/sim on any device\nand enter this code to see your shots.")
                            .font(.system(size: 12))
                            .foregroundColor(BSTheme.textMuted)
                            .lineSpacing(3)

                        Button {
                            liveSimService.regenerateCode()
                        } label: {
                            Label("New Code", systemImage: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(BSTheme.gold)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }

                    Spacer()

                    if let qrImage = qrCode(for: liveSimService.simURL?.absoluteString ?? "") {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                // Status row
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundColor(BSTheme.textMuted)
                    Spacer()
                    if liveSimService.shotsSent > 0 {
                        Text("\(liveSimService.shotsSent) shot\(liveSimService.shotsSent == 1 ? "" : "s") sent")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(BSTheme.fairwayGreen)
                    }
                }
            }
            .padding(16)
            .background(BSTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(BSTheme.electricCyan.opacity(0.30), lineWidth: 1))

            PremiumActionButton(
                title: "Hit Shot",
                icon: "camera.fill",
                style: .gradient(BSTheme.rangeGradient),
                action: onStartCamera
            )
            .glowingAccent(BSTheme.electricCyan)
        }
    }

    private var statusColor: Color {
        if liveSimService.lastBroadcastError != nil { return BSTheme.dangerRed }
        if liveSimService.isBroadcasting            { return BSTheme.gold }
        if liveSimService.shotsSent > 0             { return BSTheme.fairwayGreen }
        return BSTheme.textMuted
    }

    private var statusText: String {
        if let err = liveSimService.lastBroadcastError { return err }
        if liveSimService.isBroadcasting              { return "Broadcasting…" }
        if liveSimService.shotsSent > 0               { return "Connected — ready for next shot" }
        return "Waiting — open truecarry.app/sim on your screen"
    }

    private func qrCode(for string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
