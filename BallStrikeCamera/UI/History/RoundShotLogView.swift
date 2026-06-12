import SwiftUI
import MapKit

// MARK: - RoundShotLogView

/// Paged satellite-map view of every NFC-recorded shot in a round.
/// One page per hole that has shots; swipe left/right to move between holes.
/// When a camera shot was linked to an NFC tap, a play button appears so the
/// user can watch that shot back inline.
struct RoundShotLogView: View {
    let round: CourseRound
    /// All SavedShots for this round — used for linked-shot playback and GPS pins.
    let linkedShots: [SavedShot]

    @State private var selectedLinkedShot: SavedShot?

    private var holesWithShots: [Int] {
        let nfcHoles = round.nfcShots.map { $0.holeNumber }
        let cameraHoles = linkedShots.compactMap { shot -> Int? in
            guard shot.shotLatitude != nil, let h = shot.holeNumber else { return nil }
            return h
        }
        return Array(Set(nfcHoles + cameraHoles)).sorted()
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
                            linkedShots: linkedShots,
                            cameraShots: linkedShots.filter {
                                $0.holeNumber == holeNum && $0.shotLatitude != nil
                            },
                            mapWidth: geo.size.width,
                            onPlayShot: { selectedLinkedShot = $0 }
                        )
                        .padding(.horizontal, 2)
                        .padding(.bottom, 28)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
            .frame(height: pageHeight)
            .sheet(item: $selectedLinkedShot) { shot in
                NavigationStack {
                    ShotDetailView(shot: shot)
                }
                .tcAppearance()
            }
        }
    }

    private var pageHeight: CGFloat {
        let maxShots = holesWithShots.map { h in
            round.nfcShots.filter { $0.holeNumber == h }.count
        }.max() ?? 1
        return 46 + 220 + CGFloat(min(maxShots, 6)) * 44 + 36
    }
}

// MARK: - HoleShotPage

private struct HoleShotPage: View {
    let holeNumber: Int
    let shots: [NFCShot]
    let linkedShots: [SavedShot]
    let cameraShots: [SavedShot]
    let mapWidth: CGFloat
    let onPlayShot: (SavedShot) -> Void

    private let mapHeight: CGFloat = 220

    @State private var snapshot: UIImage?
    @State private var nfcPinPoints: [(id: UUID, point: CGPoint)] = []
    @State private var cameraPinPoints: [(id: UUID, point: CGPoint)] = []

    private var linkedShotIds: Set<UUID> {
        Set(shots.compactMap { $0.linkedShotId })
    }

    var body: some View {
        VStack(spacing: 0) {
            holeHeader

            // Satellite map with overlaid shot pins
            ZStack(alignment: .topLeading) {
                if let img = snapshot {
                    Image(uiImage: img)
                        .resizable()
                        .frame(width: mapWidth, height: mapHeight)

                    // Camera shot GPS pins (unlinked only — linked ones show via NFC pin)
                    ForEach(cameraShots.filter { !linkedShotIds.contains($0.id) }) { shot in
                        if let pt = cameraPinPoints.first(where: { $0.id == shot.id })?.point {
                            CameraShotPin(shot: shot) {
                                onPlayShot(shot)
                            }
                            .position(x: pt.x, y: pt.y - 18)
                        }
                    }

                    // NFC tap pins
                    ForEach(shots) { shot in
                        if let pt = nfcPinPoints.first(where: { $0.id == shot.id })?.point {
                            let linked = linkedShots.first(where: { $0.id == shot.linkedShotId })
                            ShotPin(shot: shot, hasVideo: linked != nil) {
                                if let s = linked { onPlayShot(s) }
                            }
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

    private var totalShotCount: Int {
        let nfcIds = Set(shots.map { $0.id })
        let cameraOnly = cameraShots.filter { !linkedShotIds.contains($0.id) }.count
        return nfcIds.count + cameraOnly
    }

    private var holeHeader: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HOLE \(holeNumber)")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(TCTheme.textMuted)
                Text("\(totalShotCount) shot\(totalShotCount == 1 ? "" : "s")")
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
                let linked = linkedShots.first(where: { $0.id == shot.linkedShotId })
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(clubColor(shot.clubName).opacity(0.18))
                            .frame(width: 30, height: 30)
                        Text("\(shot.shotNumber)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(clubColor(shot.clubName))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(shot.clubName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(TCTheme.textPrimary)
                        if let dist = shot.distanceToPinYards {
                            Text("\(Int(dist.rounded())) yd to pin")
                                .font(.system(size: 11))
                                .foregroundColor(TCTheme.textMuted)
                        }
                    }
                    Spacer()
                    if let linkedShot = linked {
                        Button {
                            onPlayShot(linkedShot)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(TCTheme.gold)
                        }
                        .buttonStyle(.plain)
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
                self.snapshot = snap.image
                self.nfcPinPoints = shots.map { s in
                    let coord = CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude)
                    return (id: s.id, point: snap.point(for: coord))
                }
                self.cameraPinPoints = cameraShots.compactMap { s in
                    guard let lat = s.shotLatitude, let lon = s.shotLongitude else { return nil }
                    let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    return (id: s.id, point: snap.point(for: coord))
                }
            }
        }
    }

    private func computeRegion() -> MKCoordinateRegion {
        var lats = shots.map { $0.latitude }
        var lons = shots.map { $0.longitude }
        for s in cameraShots {
            if let lat = s.shotLatitude, let lon = s.shotLongitude {
                lats.append(lat); lons.append(lon)
            }
        }
        guard !lats.isEmpty else {
            return MKCoordinateRegion(center: .init(latitude: 0, longitude: 0),
                                     span: .init(latitudeDelta: 0.005, longitudeDelta: 0.005))
        }
        let center = CLLocationCoordinate2D(
            latitude:  (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let spanLat = max((lats.max()! - lats.min()!) * 2.5, 0.002)
        let spanLon = max((lons.max()! - lons.min()!) * 2.5, 0.002)
        return MKCoordinateRegion(center: center,
                                  span: .init(latitudeDelta: spanLat, longitudeDelta: spanLon))
    }
}

// MARK: - ShotPin overlay

private struct ShotPin: View {
    let shot: NFCShot
    let hasVideo: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(clubColor(shot.clubName))
                        .frame(width: 28, height: 28)
                        .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 2)
                    Text("\(shot.shotNumber)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                if hasVideo {
                    Image(systemName: "video.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(3)
                        .background(Circle().fill(Color.black.opacity(0.7)))
                        .offset(x: 6, y: -6)
                }
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
        .onTapGesture { if hasVideo { onTap() } }
        .contentShape(Rectangle())
    }

    private var shotLabel: String {
        let abbr = abbreviateClub(shot.clubName)
        if let dist = shot.distanceToPinYards {
            return "\(abbr) · \(Int(dist.rounded()))y"
        }
        return abbr
    }
}

// MARK: - CameraShotPin

private struct CameraShotPin: View {
    let shot: SavedShot
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.88))
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                Image(systemName: "camera.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.black.opacity(0.75))
            }
            Text(shot.clubName.flatMap { abbreviateClub($0) } ?? "—")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
        }
        .onTapGesture { onTap() }
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
