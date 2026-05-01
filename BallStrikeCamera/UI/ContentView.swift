import SwiftUI

struct ContentView: View {
    var body: some View {
        RangeCameraScreen()
            .preferredColorScheme(.dark)
            .statusBarHidden(true)
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
        .environmentObject(CameraController())
}
