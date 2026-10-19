import CoreGraphics

/// Every gesture the app understands.
///
/// Head gestures are measured in DEGREES from your neutral position, always from
/// YOUR point of view (turning to your left is "left" no matter how the camera
/// image is mirrored; see PlayerDirections.swift).
/// Expressions are measured in PERCENT of the distance between your eyes, relative
/// to your neutral (calibrated) face, so they don't change when you sit closer or
/// further away.
enum GestureID: String, CaseIterable, Identifiable {
    case tiltUp
    case tiltDown
    case turnLeft
    case turnRight
    case mouthOpen
    case eyebrowsRaise

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiltUp: return "Tilt head up"
        case .tiltDown: return "Tilt head down"
        case .turnLeft: return "Turn head left"
        case .turnRight: return "Turn head right"
        case .mouthOpen: return "Open mouth"
        case .eyebrowsRaise: return "Raise eyebrows"
        }
    }

    var isHeadGesture: Bool {
        switch self {
        case .tiltUp, .tiltDown, .turnLeft, .turnRight: return true
        case .mouthOpen, .eyebrowsRaise: return false
        }
    }

    /// "°" for head gestures, "%" for expressions.
    var unit: String { isHeadGesture ? "°" : "%" }

    /// Thresholds used in Keys and Aim modes (Snake mode has its own, see Config.Snake).
    var thresholds: GestureThresholds {
        switch self {
        case .tiltUp: return Config.Gestures.tiltUp
        case .tiltDown: return Config.Gestures.tiltDown
        case .turnLeft: return Config.Gestures.turnLeft
        case .turnRight: return Config.Gestures.turnRight
        case .mouthOpen: return Config.Gestures.mouthOpen
        case .eyebrowsRaise: return Config.Gestures.eyebrowsRaise
        }
    }
}

/// Press / release thresholds and hold time for one gesture (see ThresholdGesture).
struct GestureThresholds {
    /// Go past this to press.
    let press: Double
    /// Come back below this to release. Must be lower than `press`.
    let release: Double
    /// Seconds you must stay past `press` before it fires.
    let holdTime: Double
}

/// How a gesture drives its output.
enum PressStyle {
    /// Held down for as long as the gesture is held (e.g. hold A to walk left).
    case hold
    /// One quick press each time the gesture fires (e.g. Snake turns).
    case tap
}

/// What a gesture does: which key/button, hold or tap, and a name for the window.
struct OutputBinding {
    let action: OutputAction
    let style: PressStyle
    let label: String

    static func hold(_ action: OutputAction, _ label: String) -> OutputBinding {
        OutputBinding(action: action, style: .hold, label: label)
    }

    static func tap(_ action: OutputAction, _ label: String) -> OutputBinding {
        OutputBinding(action: action, style: .tap, label: label)
    }

    /// e.g. "hold Space" or "tap ↑".
    var description: String {
        switch style {
        case .hold: return "hold \(label)"
        case .tap: return "tap \(label)"
        }
    }
}

/// The three ways the app can map your face to the game. Switch in the debug window.
enum ControlMode: String, CaseIterable, Identifiable {
    /// Head = Space / A / D keys, expressions = mouse click + E.
    case keys
    /// Head = mouse aiming, expressions = mouse click + E. (Head can't do both yet; Phase 3.)
    case aim
    /// Head up/down/left/right = one tap of the arrow keys, for Google Snake.
    case snake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keys: return "Keys"
        case .aim: return "Aim (mouse)"
        case .snake: return "Snake"
        }
    }

    /// Which gestures do what in this mode (edit these in Config.Mapping).
    var bindings: [GestureID: OutputBinding] {
        switch self {
        case .keys: return Config.Mapping.keys
        case .aim: return Config.Mapping.aim
        case .snake: return Config.Mapping.snake
        }
    }

    /// Thresholds for a gesture in this mode.
    func thresholds(for gesture: GestureID) -> GestureThresholds {
        if self == .snake && gesture.isHeadGesture {
            return GestureThresholds(press: Config.Snake.pressDegrees,
                                     release: Config.Snake.neutralDegrees,
                                     holdTime: Config.Snake.holdTime)
        }
        return gesture.thresholds
    }

    /// True when the head moves the mouse instead of pressing keys.
    var headMovesMouse: Bool { self == .aim }
}
