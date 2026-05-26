import SwiftUI

@main
struct PoseBridgeApp: App {
    @StateObject private var camera = CameraManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(camera)
        }
    }
}
