import AVFoundation
import ApplicationServices
import AppKit

enum CameraPermission: Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
}

/// Checks and requests the two permissions Phase 1 needs:
/// - Camera: to see your face.
/// - Accessibility: required by macOS before an app may send key presses to other apps.
///
/// IMPORTANT: when you start the app from Terminal with `swift run`, macOS gives
/// these permissions to the TERMINAL app (it's the "responsible" app), not to
/// Face Controller itself. So in System Settings you turn on "Terminal"
/// (or iTerm / Visual Studio Code, whichever you launched from).
enum Permissions {

    // MARK: Camera

    static func cameraStatus() -> CameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    /// Shows the system "would like to access the camera" prompt (first time only).
    /// `completion` runs on a background queue.
    static func requestCameraAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            completion(granted)
        }
    }

    // MARK: Accessibility (needed to send key presses)

    static func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system dialog that offers to open System Settings > Accessibility.
    static func promptForAccessibility() {
        // "AXTrustedCheckOptionPrompt" is the value of the kAXTrustedCheckOptionPrompt
        // constant. Using the plain string avoids C-pointer bridging noise.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Opening System Settings

    static func openCameraSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Which app gets the permission?

    /// Best guess at the app macOS gives the permission to (the app we were launched from).
    static var responsibleAppName: String {
        let program = ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? ""
        switch program {
        case "Apple_Terminal": return "Terminal"
        case "iTerm.app": return "iTerm"
        case "vscode": return "Visual Studio Code (or Cursor)"
        case "WarpTerminal": return "Warp"
        case "ghostty": return "Ghostty"
        case "": return "Terminal"
        default: return program
        }
    }
}
