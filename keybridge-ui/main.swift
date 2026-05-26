import SwiftUI

@main
struct KeyBridgeUI: App {
    @StateObject private var mgr = KeyBridgeManager()

    var body: some Scene {
        WindowGroup("KeyBridge 配置") {
            ContentView()
                .environmentObject(mgr)
                .frame(minWidth: 480, minHeight: 400)
        }
    }
}
