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

    /// Snake has its own fast, forgiving rules (see SnakeController.swift).
    /// The `default...` values are only the STARTING values of the live sliders and
    /// switches in the debug window: once you change one, your value is saved and
    /// used instead. ("Reset to defaults" in the window goes back to these.)
    enum Snake {
        /// Turn/tilt this many degrees from center to fire a turn.
        static let defaultPressDegrees: Double = 5
        /// After a turn, that axis re-arms once your head comes back below this
        /// fraction of the press threshold (0.45 = 45%). Only the axis that fired is checked.
        static let defaultRearmFraction: Double = 0.45
        /// Stay past the press threshold this long before a turn fires (flicks skip this).
        static let defaultHoldTime: Double = 0.030
        /// 0 = no smoothing (fastest, most jitter), 1 = heavy smoothing (slowest).
        static let defaultSmoothing: Double = 0.3
        /// A quick head flick at least this fast (degrees per second) fires a turn
        /// right away, before you reach the press threshold. 0 = flicks off.
        static let defaultFlickSpeed: Double = 60
        /// Minimum time between two turns. A turn that comes sooner is DELAYED by the
        /// rest of this time (never dropped), so fast combos like "left, then up"
        /// always arrive as two separate key presses.
        static let defaultMinTurnInterval: Double = 0.045
        /// Optional safety blocks, OFF by default: Google Snake already ignores a turn
        /// straight back (180°) and a repeat of the direction you're going, so extra
        /// taps are harmless, while these blocks were eating real fast turns.
        static let defaultBounceBlockEnabled = false
        static let defaultSameDirectionBlockEnabled = false

        /// Slider ranges.
        static let pressRange: ClosedRange<Double> = 2...12
        static let rearmRange: ClosedRange<Double> = 0.2...0.8
        static let holdRange: ClosedRange<Double> = 0...0.15
        static let smoothingRange: ClosedRange<Double> = 0...1
        static let flickSpeedRange: ClosedRange<Double> = 0...200
        static let minTurnIntervalRange: ClosedRange<Double> = 0...0.15

        /// A flick only counts once the head is at least this fraction of the press
        /// threshold away from center (ignores tiny twitches).
        static let flickMinFraction: Double = 0.3
        /// EARLY flick: fire as soon as the latest frame moves at least the flick speed
        /// AND the frame before was already moving the same way at this fraction of it.
        /// (Saves a frame compared with waiting for the two-frame average.)
        static let flickOnsetFraction: Double = 0.5
        /// BOUNCE-BACK block (only if switched on): right after an axis re-arms, a turn
        /// in the OPPOSITE direction on that axis is ignored for this long.
        static let bounceBlock: Double = 0.35
        /// DOUBLE-TURN block (only if switched on): the same direction can't fire
        /// twice within this time.
        static let sameDirectionCooldown: Double = 0.25
        /// How long each tap holds the arrow key down before releasing it.
        static let tapDuration: Double = 0.030
        /// How many lines the Turn log keeps.
        static let turnLogLength = 14
    }

    // MARK: - Floating center (all modes)

    /// The center follows your head: wherever your head comes to REST near the
    /// center becomes the new center, so moves are measured from where you are now.
    /// It never moves while a direction is firing/held or the pointer is moving.
    /// ON by default in every mode; each mode has its own off switch, and the follow
    /// speed is a slider (both in the debug window, saved between launches).
    enum FloatingCenter {
        static let defaultEnabled = true
        /// Starting value of the "Follow time" slider: about how many seconds the center
        /// takes to catch up with your resting head. Lower = follows faster.
        static let defaultFollowTime: Double = 2.0
        static let followTimeRange: ClosedRange<Double> = 0.3...8
        /// Your head must be still (slower than this, degrees per second)...
        static let stillSpeed: Double = 15
        /// ...for at least this long before the center starts following.
        static let restDwell: Double = 0.25
        /// After a direction fires (key, turn), don't follow for this long, so the
        /// settling movement isn't mistaken for a rest.
        static let pauseAfterOutput: Double = 0.3
        /// How close to the center counts as "resting near center":
        /// Keys mode: this fraction of the smallest head press threshold (10° → 5°).
        /// Aim mode: inside the aim deadzone (so the pointer never moves).
        /// Snake mode: this fraction of the re-arm zone (stricter, see below).
        static let keysZoneFraction: Double = 0.5
        static let snakeZoneFraction: Double = 0.5
        /// Snake: after a turn, the center waits this long before it may follow, so
        /// a head that's still settling after a turn can't drag the center toward
        /// that side (which would make the next turn need extra movement).
        static let snakePauseAfterTurn: Double = 0.8
    }

    // MARK: - Recenter

    /// Instantly makes "where your head is now" the new neutral (no 3-second
    /// calibration). Works in every mode. Hotkey works from any app.
    enum Recenter {
        static let keyCode = UInt32(kVK_ANSI_R)
        static let modifiers = UInt32(controlKey | optionKey | cmdKey)
        static let description = "⌃⌥⌘R  (Control + Option + Command + R)"
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
