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
    /// Head offset from YOUR point of view (what the direction pad shows).
    var playerOffset: PlayerHeadOffset?
    /// Smoothed mouth/eyebrow values (absolute, before subtracting neutral).
    var expressions: ExpressionValues?
    /// Whether the camera frames are mirrored (we correct for it automatically).
    var framesMirrored = false

    // Gestures
    var gestures: [GestureSnapshot] = []
    /// Snake mode: waiting for your head to come back to center before the next turn.
    var snakeWaitingForCenter = false

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
