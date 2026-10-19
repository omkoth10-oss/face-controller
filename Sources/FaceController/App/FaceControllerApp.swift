import AppKit
import SwiftUI

/// Program entry point (`@main`).
///
/// We use SwiftUI for the window, plus a classic AppKit "app delegate" for the
/// parts SwiftUI doesn't cover: becoming a normal Dock app when launched from
/// Terminal, and running cleanup code when the app quits.
@main
struct FaceControllerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Face Controller (debug)", id: "debug") {
            DebugView(model: appDelegate.controller.model, controller: appDelegate.controller)
                .frame(minWidth: 700, minHeight: 500)
        }
        // Opens big enough for all three columns; resizable, and scrolls if smaller.
        .defaultSize(width: 1340, height: 920)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A program started from Terminal isn't a "real" app bundle, so by default
        // macOS gives it no Dock icon and doesn't bring its window to the front.
        // `.regular` makes it behave like a normal app with a window and Dock icon.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        controller.start()

        // Closing the debug window quits the app (and releases everything), even
        // while the game overlay panel is still on screen.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(windowWillClose(_:)),
                                               name: NSWindow.willCloseNotification,
                                               object: nil)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, !(window is NSPanel),
              window.title.hasPrefix("Face Controller") else { return }
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true  // Closing the window quits the app (and releases all keys).
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }
}
