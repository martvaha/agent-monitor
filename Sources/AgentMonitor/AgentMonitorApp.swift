import AppKit

@main
enum AgentMonitorApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // Settings live in the status panel. A SwiftUI Settings scene creates
        // an empty standalone window that macOS can open at launch or reopen.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

/// Makes the process a menu-bar agent (no Dock icon, no main window), installs
/// the status item and starts the usage refresh loop at launch so the label
/// populates without a click.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if Snapshot.runIfRequested() { exit(0) }
        #endif
        statusItem = StatusItemController(store: .shared, codexStore: .shared)
        UsageStore.shared.start()
        CodexStore.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Reopening the app should leave it in the menu bar until clicked.
        false
    }
}
