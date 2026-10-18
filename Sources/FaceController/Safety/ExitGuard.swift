import Foundation

/// Makes sure no key is left held down when the app exits.
///
/// Ways the app can end, and what catches each one:
/// - Cmd+Q / closing the window  -> `applicationWillTerminate` (AppDelegate) + `atexit`
/// - Ctrl+C in Terminal          -> SIGINT handler below
/// - Closing the Terminal window -> SIGHUP handler below
/// - `kill <pid>`                -> SIGTERM handler below
/// - Any call to `exit()`        -> `atexit` handler below
///
/// What can NOT be caught: a crash or `kill -9`. If that ever leaves Space
/// stuck, just tap the real Space bar once and it's released.
enum ExitGuard {
    private static var keyboard: KeyboardOutput?
    private static var signalSources: [DispatchSourceSignal] = []
    private static var installed = false

    /// Call once at startup.
    static func install(keyboard: KeyboardOutput) {
        guard !installed else { return }
        installed = true
        self.keyboard = keyboard

        // Runs when the process exits normally (including after NSApp.terminate).
        atexit {
            ExitGuard.releaseEverything()
        }

        // Signals: normally Ctrl+C kills the process instantly, with no chance to
        // release keys. We tell the system to ignore the default action, then handle
        // the signal ourselves on the main queue: release keys, then exit.
        for signalNumber in [SIGINT, SIGTERM, SIGHUP, SIGQUIT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                ExitGuard.releaseEverything()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// Releases every held key and blocks new presses for good. Safe to call many times.
    static func releaseEverything() {
        keyboard?.setBlocked(.shuttingDown, true)
    }
}
