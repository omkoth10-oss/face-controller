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

        /// Read facial expressions (mouth, eyebrows) with Vision face landmarks.
        /// Turning this off saves a few milliseconds per frame.
        static let expressionsEnabled = true
    }

    // MARK: - Directions (always from the PLAYER's point of view)

    /// Turning your head to YOUR left is "left" and tilting YOUR head up is "up",
    /// whatever the camera does. The app already corrects for mirrored camera frames.
    /// Use the direction pad in the debug window to check. Only if a camera still
    /// comes out backwards, flip it here.
    enum Directions {
        /// Set to true if turning your head to YOUR left shows RIGHT on the direction pad.
        static let flipHorizontal = false
        /// Set to true if tilting your head UP shows DOWN on the direction pad.
        static let flipVertical = false
    }

    // MARK: - Smoothing (One Euro filter)

    /// Light smoothing to remove jitter. The One Euro filter smooths a lot when you're
    /// still (removes jitter) and almost not at all when you move fast (keeps it responsive).
    enum Smoothing {
        /// Set to false to use the raw Vision values with zero smoothing.
        static let enabled = true

        /// How much jitter is removed when still. Lower = smoother but laggier.
        /// Measured in Hz (bigger number = less smoothing).
        static let minCutoff: Double = 2.5

        /// How quickly smoothing switches off when the HEAD moves fast (degrees).
        /// Bigger = more responsive during fast movements (but a bit more jitter).
        static let beta: Double = 0.1

        /// Same idea for EXPRESSIONS (measured in % of eye distance, a different scale).
        static let expressionBeta: Double = 0.03

        /// Smoothing used internally for the speed estimate. Rarely needs changing.
        static let derivativeCutoff: Double = 1.0

        /// If the face disappears for longer than this, the filter starts fresh
        /// instead of blending in old values.
        static let resetAfterGap: Double = 0.25
    }

    // MARK: - Calibration

    enum Calibration {
        /// How long (seconds of face-visible time) to record your neutral face.
        static let duration: Double = 3.0
    }

    // MARK: - Gesture thresholds (Keys and Aim modes)

    /// press   = go past this to press (degrees for the head, % for expressions)
    /// release = come back below this to release (keep it a few units below press;
    ///           the gap stops flickering)
    /// holdTime = seconds you must stay past `press` before it fires
    ///            (filters out accidental twitches). Releasing is always immediate.
    enum Gestures {
        static let tiltUp = GestureThresholds(press: 10, release: 6, holdTime: 0.080)
        static let tiltDown = GestureThresholds(press: 10, release: 6, holdTime: 0.080)
        static let turnLeft = GestureThresholds(press: 10, release: 6, holdTime: 0.080)
        static let turnRight = GestureThresholds(press: 10, release: 6, holdTime: 0.080)

        /// Mouth: gap between the lips, in % of the distance between your eyes,
        /// above your calibrated (closed) mouth. A clearly open mouth is ~40–60%.
        static let mouthOpen = GestureThresholds(press: 30, release: 18, holdTime: 0.080)

        /// Eyebrows: how far they rise above your calibrated position, in % of the
        /// distance between your eyes. A clear raise is roughly 8–15%.
        static let eyebrowsRaise = GestureThresholds(press: 8, release: 5, holdTime: 0.080)
    }

    // MARK: - What each gesture does, per mode

    enum Mapping {
        /// Mode the app starts in.
        static let startMode: ControlMode = .keys

        /// Keys mode: head = movement keys, expressions = actions.
        static let keys: [GestureID: OutputBinding] = [
            .tiltUp: .hold(.key(CGKeyCode(kVK_Space)), "Space"),
            .turnLeft: .hold(.key(CGKeyCode(kVK_ANSI_A)), "A"),
            .turnRight: .hold(.key(CGKeyCode(kVK_ANSI_D)), "D"),
            .mouthOpen: .hold(.leftMouseButton, "left mouse"),
            .eyebrowsRaise: .hold(.key(CGKeyCode(kVK_ANSI_E)), "E"),
        ]

        /// Aim mode: the head moves the mouse (see Aim below), so head gestures are off.
        static let aim: [GestureID: OutputBinding] = [
            .mouthOpen: .hold(.leftMouseButton, "left mouse"),
            .eyebrowsRaise: .hold(.key(CGKeyCode(kVK_ANSI_E)), "E"),
        ]

        /// Snake mode: one tap of an arrow key per head movement. Expressions are off.
        static let snake: [GestureID: OutputBinding] = [
            .tiltUp: .tap(.key(CGKeyCode(kVK_UpArrow)), "↑"),
            .tiltDown: .tap(.key(CGKeyCode(kVK_DownArrow)), "↓"),
            .turnLeft: .tap(.key(CGKeyCode(kVK_LeftArrow)), "←"),
            .turnRight: .tap(.key(CGKeyCode(kVK_RightArrow)), "→"),
        ]
    }

    // MARK: - Snake mode

    enum Snake {
        /// Move your head this many degrees (any direction) to send one arrow-key tap.
        static let pressDegrees: Double = 10
        /// After a tap, your head must come back within this many degrees of neutral
        /// (on BOTH axes) before the next direction can fire. Prevents spamming turns.
        static let neutralDegrees: Double = 5
        /// Must stay past `pressDegrees` this long before the tap fires.
        static let holdTime: Double = 0.050
        /// How long each tap holds the key down before releasing it.
        static let tapDuration: Double = 0.030
    }

    // MARK: - Head-to-mouse aiming (Aim mode)

    /// The head works like a joystick: the further you turn/tilt past the deadzone,
    /// the faster the pointer moves. Return to neutral and it stops.
    enum Aim {
        /// Overall speed multiplier. The slider in the debug window starts here.
        static let defaultSensitivity: Double = 1.0
        static let sensitivityRange: ClosedRange<Double> = 0.25...3.0

        /// No movement within this many degrees of neutral (so small wobbles don't drift).
        static let horizontalDeadzone: Double = 2.5
        static let verticalDeadzone: Double = 2.0

        /// At this many degrees (and beyond) the pointer moves at full speed.
        static let horizontalFullSpeedAngle: Double = 15
        static let verticalFullSpeedAngle: Double = 10

        /// Full speed, in screen points per second (at sensitivity 1.0).
        static let maxSpeedX: Double = 1500
        static let maxSpeedY: Double = 1000

        /// Response curve between the deadzone and full speed:
        /// 1.0 = straight line; higher = slower and more precise near the center,
        /// then speeding up quickly further out.
        static let curveExponent: Double = 1.8

        /// Eases speed changes over this many seconds so the pointer doesn't jerk
        /// between camera frames. 0 = no extra smoothing. Stopping is always instant.
        static let smoothingTime: Double = 0.05

        /// How many mouse-move events per second we send (smoother than the camera's 30–60).
        static let outputRate: Double = 120

        /// If no fresh head data arrives for this long, the pointer stops (safety).
        static let staleAfter: Double = 0.12
    }

    // MARK: - Safety

    enum Safety {
        /// If no face is seen for longer than this, everything held is released.
        static let faceLostTimeout: Double = 0.200

        /// How often the safety watchdog checks for a lost face / frozen camera.
        static let watchdogInterval: Double = 0.050

        /// How often we re-check Camera and Accessibility permissions.
        static let permissionCheckInterval: Double = 0.5

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

        /// How long a tap shows as "TAP" in the gesture table.
        static let tapFlashDuration: Double = 0.3
    }
}
