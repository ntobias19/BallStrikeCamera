import SwiftUI

struct RangeCameraScreen: View {
    @EnvironmentObject private var camera: CameraController
    @State private var selectedClub = "7 Iron"

    var body: some View {
        LaunchMonitorScaffoldView(
            camera: camera,
            modeTitle: "Range",
            selectedClub: $selectedClub,
            shotCount: 12
        )
    }
}
