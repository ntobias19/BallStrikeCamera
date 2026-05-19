import SwiftUI

/// DEBUG-only diagnostics overlay for the GPS hole screen.
/// Compiled out of release builds entirely.
#if DEBUG

struct DiagnosticsOverlay: View {
    let hole: GolfHole?
    let courseSource: CourseSource?
    @ObservedObject var telemetry: OSMTelemetry = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("hole",      hole.map { "\($0.number)  par \($0.par)" } ?? "—")
            row("yards",     hole?.measuredYardage.map { "\($0)" } ?? hole?.teeYardsByTeeBox.values.first.map(String.init) ?? "—")
            row("source",    courseSource?.rawValue ?? "—")
            row("conf",      confidenceLabel)
            row("polygons",  polygonCounts)
            row("mirror",    telemetry.lastMirror ?? "—")
            row("lat",       telemetry.lastEnrichLatencyMs.map { "\($0) ms" } ?? "—")
            row("cache",     cacheLabel)
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(.green.opacity(0.95))
        .padding(8)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(.green.opacity(0.40), lineWidth: 0.5))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(spacing: 6) {
            Text(k.uppercased())
                .frame(width: 56, alignment: .leading)
                .foregroundColor(.green.opacity(0.55))
            Text(v).foregroundColor(.green)
        }
    }

    private var confidenceLabel: String {
        guard let h = hole else { return "—" }
        if h.greenPolygon != nil && h.fairwayPolygon != nil { return "high" }
        if h.greenPolygon != nil { return "mid" }
        return "low"
    }

    private var polygonCounts: String {
        guard let h = hole else { return "—" }
        return "g:\(h.greenPolygon == nil ? 0 : 1) f:\(h.fairwayPolygon == nil ? 0 : 1) b:\(h.bunkerPolygons.count) w:\(h.waterPolygons.count)"
    }

    private var cacheLabel: String {
        guard let entry = telemetry.recent.first else { return "—" }
        return entry.status.rawValue
    }
}

#endif
