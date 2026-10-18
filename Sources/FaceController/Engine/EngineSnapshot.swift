import Foundation

enum CalibrationState: Equatable {
    case notStarted
    case inProgress(progress: Double, faceVisible: Bool)
    case done(CalibrationResult)
}

/// A copy of everything the debug window shows, taken on the tracking queue and
/// handed to the window. Because it's a plain value (a struct), the window can read
/// it safely while the tracking loop keeps running on its own thread.
struct EngineSnapshot {
    // Calibration
    var calibration: CalibrationState = .notStarted

    // Face
    var faceVisible = false
    var faceConfidence: Float = 0
    /// Vision found a face but didn't report head angles.
    var anglesMissing = false
    /// Raw angles from Vision (degrees).
    var rawAngles: HeadAngles?
    /// Smoothed angles minus your neutral position (degrees).
    var relativeAngles: HeadAngles?

    // Gesture: tilt up -> Space
    var tiltUpDegrees: Double?
    var gesturePhase: GesturePhase = .waitingForNeutral
    var keyHeld = false

    // Safety
    var blockReasons: [InputBlockReason] = []
    /// Newest first, e.g. "12:01:33  Released Space: face lost".
    var recentEvents: [String] = []

    // Performance (milliseconds unless noted)
    var cameraFPS: Double = 0
    var droppedFrames = 0
    var secondsSinceLastFrame: Double?
    var visionMs: Double?
    var processingMs: Double?
    var processingMaxMs: Double?
    /// How old a frame already is when it reaches us (camera + driver delay).
    var cameraDelayMs: Double?
    /// Camera frame captured -> key event sent, for the most recent key event.
    var lastKeyLatencyMs: Double?
    var averageKeyLatencyMs: Double?
    var keyEventCount = 0
    var visionError: String?
}
