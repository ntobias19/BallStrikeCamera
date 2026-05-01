import SwiftUI

@main
struct BallStrikeCameraApp: App {
    @StateObject private var camera = CameraController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(camera)
                .onAppear { camera.start() }
                .onDisappear { camera.stop() }
        }
    }
}
