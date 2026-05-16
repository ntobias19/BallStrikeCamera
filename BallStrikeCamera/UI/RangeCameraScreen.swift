import SwiftUI

struct RangeCameraScreen: View {
    @EnvironmentObject private var camera: CameraController
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClub = "7 Iron"

    var context: ShotContext? = nil
    var onShotComplete: (() -> Void)? = nil

    var body: some View {
        LaunchMonitorScaffoldView(
            camera: camera,
            modeTitle: context?.sourceMode == .course ? "Course" : "Range",
            selectedClub: $selectedClub,
            shotCount: 12,
            context: context,
            onDismiss: {
                OrientationManager.shared.lockPortrait()
                dismiss()
            },
            onShotComplete: {
                onShotComplete?()
                OrientationManager.shared.lockPortrait()
                dismiss()
            }
        )
        .onAppear  { OrientationManager.shared.lockLandscape() }
        .onDisappear { OrientationManager.shared.lockPortrait() }
    }
}
