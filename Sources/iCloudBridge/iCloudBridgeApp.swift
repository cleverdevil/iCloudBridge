import SwiftUI

@main
struct iCloudBridgeApp: App {
    var body: some Scene {
        MenuBarExtra("iCloud Bridge", systemImage: "cloud") {
            Text("iCloud Bridge")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
