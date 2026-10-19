import Foundation

enum CalibrationState: Equatable {
    case notStarted
    case inProgress(progress: Double, faceVisible: Bool)
    case done(CalibrationResult)
}

/// One row of the gesture table in the debug window.
struct GestureSnapshot: Identifiable {
    let gesture: GestureID
    /// Live value relative to neutral (degrees or %), nil if not measured this frame.
    let value: Double?
    let thresholds: GestureThresholds
    /// What it does in the current mode, nil if it's off in this mode.
    let binding: OutputBinding?
    let phase: GesturePhase
    /// True while its key/button is held, or for a moment after a tap.
    let firing: Bool

    var id: GestureID { gesture }
}

/// One line of the Snake Turn log.
struct TurnLogEntry: Identifiable {
    let id: Int
    /// e.g. "12:01:33.482"
    let time: String
    /// e.g. "LEFT by flick (85°/s)" or "RIGHT blocked: bounce-back after LEFT"
    let text: String
    let fired: Bool
    /// Camera frame → key event, for turns that fired.
    let latencyMs: Double?
    /// Not fired because the extra-turn guard judged it a side effect of another
    /// movement (orange), rather than a real turn being blocked (red).
    let ignoredExtra: Bool
    /// How far the head went for this turn, filled in once it comes back.
    var reachedDegrees: Double? = nil
}

/// Snake mode's live state, for the Snake tuning panel.
struct SnakeStatus {
    /// Why nothing can fire at all right now (control off, no face...), nil if nothing blocks.
    var blocker: String?
    /// Per-axis plain-language state, e.g. "waiting: left/right still at 4.2° toward LEFT, needs < 2.3° to re-arm".
    var horizontalText = "—"
    var verticalText = "—"
    var horizontalArmed = false
    var verticalArmed = false
    /// Head speed per axis (degrees per second), handy for tuning the flick speed.
    var horizontalSpeed: Double = 0
    var verticalSpeed: Double = 0
    /// e.g. "LEFT by flick (85°/s)".
    var lastTurn: String?
    var secondsSinceLastTurn: Double?
    var lastTurnLatencyMs: Double?
    var averageTurnLatencyMs: Double?
    var turnCount = 0
    var flickTurnCount = 0
    var blockedCount = 0
    var ignoredExtraCount = 0
    /// Newest first.
    var turnLog: [TurnLogEntry] = []
}

/// A copy of everything the debug window shows, taken on the tracking queue and
/// handed to the window. Because it's a plain value (a struct), the window can read
/// it safely while the tracking loop keeps running on its own thread.
struct EngineSnapshot {
    var mode: ControlMode = Config.Mapping.startMode

    // Calibration
    var calibration: CalibrationState = .notStarted

    // Face
    var faceVisible = false
    var faceConfidence: Float = 0
    /// Vision found a face but didn't report head angles.
    var anglesMissing = false
    /// Raw angles from Vision (degrees).
    var rawAngles: HeadAngles?
    /// Smoothed angles minus your neutral position (degrees, camera's view).
    var relativeAngles: HeadAngles?
    /// Head offset from YOUR point of view, measured from the current center.
    var playerOffset: PlayerHeadOffset?
    /// Where the (floating) center is now, compared with your last calibration or
    /// recenter, from YOUR point of view. The Direction pad draws it as a ring.
    var centerShift: PlayerHeadOffset?
    var floatingCenter = FloatingCenterStatus()
    /// Smoothed mouth/eyebrow values (absolute, before subtracting neutral).
    var expressions: ExpressionValues?
    /// Whether the camera frames are mirrored (we correct for it automatically).
    var framesMirrored = false

    // Gestures
    var gestures: [GestureSnapshot] = []
    /// Snake mode's live state (only filled in Snake mode).
    var snake = SnakeStatus()

    // Aiming
    var aim = AimState()

    // Safety
    var blockReasons: [InputBlockReason] = []
    /// Newest first, e.g. "12:01:33  Released everything: face lost".
    var recentEvents: [String] = []

    // Performance (milliseconds unless noted)
    var cameraFPS: Double = 0
    var droppedFrames = 0
    var secondsSinceLastFrame: Double?
    var visionMs: Double?
    var landmarksMs: Double?
    var processingMs: Double?
    var processingMaxMs: Double?
    /// How old a frame already is when it reaches us (camera + driver delay).
    var cameraDelayMs: Double?
    /// Camera frame captured -> key/mouse event sent, for the most recent event.
    var lastOutputLatencyMs: Double?
    var averageOutputLatencyMs: Double?
    var outputEventCount = 0
    var visionError: String?
}
