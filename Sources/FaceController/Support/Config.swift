import CoreGraphics
import Carbon.HIToolbox  // Key codes (kVK_...) and hotkey modifier masks (cmdKey, ...).

/// Every number you might want to tune lives in this one file.
///
/// After changing a value, stop the app and run `swift run` again.
/// The README explains what each group does and how to tune it.
enum Config {

    // MARK: - Camera

    enum Camera {
        /// Frame rate we ask the camera for. Higher = less waiting between frames.
        /// Most built-in Mac cameras top out at 30 fps; many USB webcams can do 60.
        /// If 60 isn't available the app automatically uses the fastest rate the camera offers.
        static let preferredFrameRate: Double = 60

        /// Target resolution. Smaller images are faster for Vision to process.
        /// We pick the camera mode closest to this (but not smaller than the minimums below).
        static let preferredWidth: Int32 = 640
        static let preferredHeight: Int32 = 480

        /// Ignore camera modes smaller than this (too little detail for reliable tracking).
        static let minimumWidth: Int32 = 480
        static let minimumHeight: Int32 = 360

        /// Ignore camera modes wider than this when choosing a format (too slow to process).
        static let maximumWidth: Int32 = 1280
    }

    // MARK: - Face tracking

    enum Tracking {
        /// Faces that Vision is less confident about than this are ignored.
        /// (0 = accept anything, 1 = only perfect detections.)
        static let minimumFaceConfidence: Float = 0.3
    }

    // MARK: - Smoothing (One Euro filter)

    /// Light smoothing to remove jitter from the head angles.
    /// The One Euro filter smooths a lot when your head is still (removes jitter)
    /// and almost not at all when your head moves fast (keeps it responsive).
    enum Smoothing {
        /// Set to false to use the raw Vision angles with zero smoothing.
        static let enabled = true

        /// How much jitter is removed when the head is still. Lower = smoother but laggier.
        /// Measured in Hz (bigger number = less smoothing).
        static let minCutoff: Double = 2.5

        /// How quickly smoothing switches off when the head moves fast.
        /// Bigger = more responsive during fast movements (but a bit more jitter).
        static let beta: Double = 0.1

        /// Smoothing used internally for the speed estimate. Rarely needs changing.
        static let derivativeCutoff: Double = 1.0

        /// If the face disappears for longer than this, the filter starts fresh
        /// instead of blending in old values.
        static let resetAfterGap: Double = 0.25
    }

    // MARK: - Calibration

    enum Calibration {
        /// How long (seconds of face-visible time) to record your neutral head position.
        static let duration: Double = 3.0
    }

    // MARK: - Gesture: tilt head UP = hold Space

    enum TiltUp {
        /// The key that is held while your head is tilted up.
        static let key = CGKeyCode(kVK_Space)
        static let keyName = "Space"

        /// Tilt up at least this many degrees (from your neutral position) to PRESS.
        static let pressDegrees: Double = 10

        /// Come back below this many degrees to RELEASE.
        /// Must be lower than `pressDegrees`. The gap between the two ("hysteresis")
        /// stops the key from flickering on/off when you hover near the threshold.
        static let releaseDegrees: Double = 6

        /// You must stay past `pressDegrees` for this long before the key is pressed.
        /// Filters out tiny accidental twitches. 0.080 = 80 milliseconds.
        static let holdTime: Double = 0.080

        /// Vision doesn't document which pitch direction is positive.
        /// We assume tilting your head UP makes Vision's pitch go DOWN (negative).
        /// If the "Tilt up" number in the debug window goes NEGATIVE when you tilt up,
        /// change this to `true`.
        static let flipDirection = false
    }

    // MARK: - Safety

    enum Safety {
        /// If no face is seen for longer than this, every held key is released.
        static let faceLostTimeout: Double = 0.200

        /// How often the safety watchdog checks for a lost face / frozen camera.
        static let watchdogInterval: Double = 0.050

        /// How often we re-check Camera and Accessibility permissions.
        static let permissionCheckInterval: Double = 1.0

        /// Whether control turns on by itself after the first calibration finishes.
        /// You can always toggle it with the kill-switch hotkey.
        static let startWithControlOn = true

        /// Global kill switch: Control + Option + Command + K.
        /// Works from any app (even full-screen games). Toggles control ON/OFF.
        /// (Carbon key code + modifier mask, see Carbon's Events.h for other keys.)
        static let killSwitchKeyCode = UInt32(kVK_ANSI_K)
        static let killSwitchModifiers = UInt32(controlKey | optionKey | cmdKey)
        static let killSwitchDescription = "⌃⌥⌘K  (Control + Option + Command + K)"
    }

    // MARK: - Debug window

    enum UI {
        /// How often the debug window refreshes (seconds). The tracking loop itself
        /// runs at full camera speed no matter what this is set to.
        static let refreshInterval: Double = 1.0 / 30.0

        /// How many recent samples are averaged for the timing numbers.
        static let statsWindow = 30
    }
}
