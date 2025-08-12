import SwiftUI

@main
struct P2TTranscriberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("P2T", systemImage: "mic.fill") {
            ContentView()
                .frame(width: 320)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prepare early for mic permission prompt later
    }
}
