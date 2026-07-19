import AppKit
import SwiftUI

struct MenuBarMenuView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open Dashboard") {
            openDashboard()
        }

        Button("Run Quick Check") {
            appModel.runQuickCheck()
            openDashboard()
        }

        Button("Generate Report") {
            appModel.generateReport(openAfterCreate: true)
        }

        Button("Open Latest Report") {
            if !appModel.openLatestReport() {
                openDashboard()
            }
        }

        Button("Preferences") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func openDashboard() {
        openWindow(id: AppScene.dashboard)
        NSApp.activate(ignoringOtherApps: true)
    }
}
