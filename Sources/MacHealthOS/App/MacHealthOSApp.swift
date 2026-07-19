import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct MacHealthOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("Mac Health OS", id: AppScene.dashboard) {
            DashboardView()
                .environment(appModel)
        }
        .defaultSize(width: 920, height: 620)

        Settings {
            PreferencesView()
                .environment(appModel)
        }

        MenuBarExtra {
            MenuBarMenuView()
                .environment(appModel)
        } label: {
            Label("Mac Health OS", systemImage: "heart.text.square")
        }
    }
}
