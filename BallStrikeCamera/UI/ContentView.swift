import SwiftUI

struct ContentView: View {
    @State private var launchComplete = false

    var body: some View {
        ZStack {
            AppRootView(launchComplete: launchComplete)

            if !launchComplete {
                TrueCarryLaunchView {
                    withAnimation(.easeInOut(duration: 0.6)) { launchComplete = true }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthSessionStore())
        .environmentObject(CameraController())
}
