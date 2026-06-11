import SwiftUI
import MapKit

// MARK: - RoundShotLogView

/// Paged satellite-map view of every NFC-recorded shot in a round.
/// One page per hole that has shots; swipe left/right to move between holes.
struct RoundShotLogView: View {
    let round: CourseRound

    private var holesWithShots: [Int] {
        Array(Set(round.nfcShots.map { $0.holeNumber })).sorted()
    }

    var body: some View {
        if holesWithShots.isEmpty {
            Text("No club taps recorded — tap your club to the RFID hub while on-course to log shots.")
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textMuted)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            GeometryReader { geo in
                TabView {
                    ForEach(holesWithShots, id: \.self) { holeNum in
                        HoleShotPage(
                            holeNumber: holeNum,
                            shots: round.nfcShots
                                .filter { $0.holeNumber == holeNum }
                                .sorted { $0.shotNumber < $1.shotNumber },
                            mapWidth: geo.size.width
                        )
                        .padding(.horizontal, 2)
                        .padding(.bottom, 28) // room for page indicator dots
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
            .frame(height: pageHeight)
        }
    }

    private var pageHeight: CGFloat {
        let maxShots = holesWithShots.map { h in
            round.nfcShots.filter { $0.holeNumber == h }.count
        }.max() ?? 1
        let clampedShots = min(maxShots, 6)
        return 46 + 220 + CGFloat(clampedShots) * 44 + 36  // header + map + rows + dots
    }
}

// MARK: - HoleShotPage

private struct HoleShotPage: View {
    let holeNumber: Int
    let shots: [NFCShot]
    let mapWidth: CGFloat

    private let mapHeight: CGFloat = 220

    @State private var snapshot: UIImage?
    @State private var pinPoints: [(id: UUID, point: CGPoint)] = []

    var body: some View {
        VStack(spacing: 0) {
            holeHeader

            // Satellite map with shot pins
            ZStack(alignment: .topLeading) {
                if let img = snapshot {
                    Image(uiImage: img)
                        .resizable()
                        .frame(width: mapWidth, height: mapHeight)
                    ForEach(shots) { shot in
                        if let pt = pinPoints.first(where: { $0.id == shot.id })?.point {
                            ShotPin(shot: shot)
                                .position(x: pt.x, y: pt.y - 22)
                        }
                    }
                } else {
                    ZStack {
                        Rectangle().fill(Color(white: 0.12))
                        ProgressView().tint(.white)
                    }
                    .frame(width: mapWidth, height: mapHeight)
                }
            }
            .frame(width: mapWidth, height: mapHeight)
            .clipped()
            .onAppear { if snapshot == nil { renderSnapshot() } }

            shotList
        }
        .background(TCTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Sub-views

    private var holeHeader: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HOLE \(holeNumber)")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(TCTheme.textMuted)
                Text("\(shots.count) shot\(shots.count == 1 ? "" : "s")")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
            }
            Spacer()
            if let closest = shots.compactMap({ $0.distanceToPinYards }).min() {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("CLOSEST")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(TCTheme.textMuted)
                    Text("\(Int(closest.rounded())) yd")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var shotList: some View {
        VStack(spacing: 0) {
            ForEach(Array(shots.enumerated()), id: \.element.id) { idx, shot in
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(clubColor(shot.clubName).opacity(0.18))
                            .frame(width: 30, height: 30)
                        Text("\(shot.shotNumber)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(clubColor(shot.clubName))
                    }
                    Text(shot.clubName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                    Spacer()
                    if let dist = shot.distanceToPinYards {
                        Text("\(Int(dist.rounded())) yd to pin")
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.textMuted)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                if idx < shots.count - 1 {
                    Rectangle()
                        .fill(TCTheme.border)
                        .frame(height: 1)
                        .padding(.leading, 54)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Snapshot

    private func renderSnapshot() {
        let region = computeRegion()
        let opts = MKMapSnapshotter.Options()
        opts.region  = region
        opts.size    = CGSize(width: mapWidth, height: mapHeight)
        opts.scale   = UIScreen.main.scale
        opts.mapType = .hybrid

        MKMapSnapshotter(options: opts).start { snap, _ in
            guard let snap else { return }
            DispatchQueue.main.async {
                self.snapshot   = snap.image
                self.pinPoints  = shots.map { s in
                    let coord = CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude)
                    return (id: s.id, point: snap.point(for: coord))
                }
            }
        }
    }

    private func computeRegion() -> MKCoordinateRegion {
        let lats = shots.map { $0.latitude }
        let lons = shots.map { $0.longitude }
        guard !lats.isEmpty else {
            return MKCoordinateRegion(center: .init(latitude: 0, longitude: 0),
                                     span: .init(latitudeDelta: 0.005, longitudeDelta: 0.005))
        }
        let center = CLLocationCoordinate2D(
            latitude:  (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        // At least ~200m wide so single-shot holes show useful context
        let spanLat = max((lats.max()! - lats.min()!) * 2.5, 0.002)
        let spanLon = max((lons.max()! - lons.min()!) * 2.5, 0.002)
        return MKCoordinateRegion(center: center,
                                  span: .init(latitudeDelta: spanLat, longitudeDelta: spanLon))
    }
}

// MARK: - ShotPin overlay view

private struct ShotPin: View {
    let shot: NFCShot

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(clubColor(shot.clubName))
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 2)
                Text("\(shot.shotNumber)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(shotLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.62))
                .clipShape(Capsule())
        }
    }

    private var shotLabel: String {
        let abbr = abbreviateClub(shot.clubName)
        if let dist = shot.distanceToPinYards {
            return "\(abbr) · \(Int(dist.rounded()))y"
        }
        return abbr
    }
}

// MARK: - Helpers

private func clubColor(_ name: String) -> Color {
    let l = name.lowercased()
    if l.contains("driver")  { return ClubType.driver.color }
    if l.contains("wood")    { return ClubType.fairwayWood.color }
    if l.contains("hybrid")  { return ClubType.hybrid.color }
    if l.contains("putter")  { return ClubType.putter.color }
    if l.contains("wedge") || l == "pw" || l == "gw" || l == "sw" || l == "lw" {
        return ClubType.wedge.color
    }
    if l.contains("iron")    { return ClubType.iron.color }
    return Color(white: 0.55)
}

private func abbreviateClub(_ name: String) -> String {
    let map: [String: String] = [
        "Driver": "Dr",  "3 Wood": "3W",  "5 Wood": "5W",  "7 Wood": "7W",
        "3 Iron": "3i",  "4 Iron": "4i",  "5 Iron": "5i",  "6 Iron": "6i",
        "7 Iron": "7i",  "8 Iron": "8i",  "9 Iron": "9i",
        "Pitching Wedge": "PW", "Gap Wedge": "GW",
        "Sand Wedge": "SW",     "Lob Wedge": "LW",
        "Putter": "Pt"
    ]
    return map[name] ?? (name.count <= 3 ? name : String(name.prefix(2)))
}
