import CoreMedia
import CoreVideo
import Foundation

/// The tight loop: camera frame -> Vision -> smoothing -> gesture -> key event.
///
/// THREADING (the tricky part, in plain language):
/// Everything in this class runs on ONE background queue, `queue`. The camera
/// delivers frames straight onto it, the safety watchdog runs on it, and the
/// public methods (recalibrate, etc.) hop onto it with `queue.async`.
/// Because only one thing ever runs on that queue at a time, the engine's
/// variables can't be changed by two threads at once, so no locks are needed here.
/// The window never touches these variables; it only receives copies (snapshots).
///
/// There's no waiting anywhere in the loop: each frame is processed the moment it
/// arrives and the key event is sent from the same function call.
final class ControlEngine {

    /// High priority ("user interactive") because latency matters.
    let queue = DispatchQueue(label: "FaceController.tracking", qos: .userInteractive)

    /// Called on `queue` with a fresh copy of the state (about 30 times a second).
    var onSnapshot: ((EngineSnapshot) -> Void)?

    private let keyboard: KeyboardOutput
    private let tracker = HeadPoseTracker()
    private var filter = HeadAnglesFilter()
    private var calibrator = Calibrator()
    private var calibration: CalibrationResult?
    private var tiltUp = ThresholdGesture(pressThreshold: Config.TiltUp.pressDegrees,
                                          releaseThreshold: Config.TiltUp.releaseDegrees,
                                          holdTime: Config.TiltUp.holdTime)

    private var lastFaceSeenAt: Double?
    private var lastFrameAt: Double?
    private var watchdog: DispatchSourceTimer?

    private var snapshot = EngineSnapshot()
    private var lastPublishAt: Double = 0

    // Performance measurements.
    private var fpsCounter = RateCounter()
    private var visionTimes = RollingAverage()
    private var processingTimes = RollingAverage()
    private var cameraDelays = RollingAverage()
    private var keyLatencies = RollingAverage()
    private var droppedFrames = 0

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init(keyboard: KeyboardOutput) {
        self.keyboard = keyboard
    }

    // MARK: - Public (safe to call from any thread)

    /// Starts the first calibration and the safety watchdog.
    func start() {
        queue.async {
            self.beginCalibration()
            self.startWatchdog()
        }
    }

    /// Records a new neutral head position (the C key / Recalibrate button).
    func recalibrate() {
        queue.async { self.beginCalibration() }
    }

    /// Call after control is turned on or off. The KeyboardOutput has already
    /// released keys; this makes the gesture wait for neutral before firing again.
    func controlWasToggled(isOn: Bool) {
        queue.async {
            self.tiltUp.reset(requireNeutral: true)
            self.logEvent(isOn ? "Control turned ON" : "Control turned OFF (all keys released)")
            self.publish(force: true)
        }
    }

    /// Adds a line to the safety/event log shown in the debug window.
    func noteEvent(_ text: String) {
        queue.async {
            self.logEvent(text)
            self.publish(force: true)
        }
    }

    // MARK: - Camera callbacks (called on `queue` by CameraManager)

    func frameDropped() {
        droppedFrames += 1
    }

    /// Processes one camera frame from start to finish.
    func process(_ sampleBuffer: CMSampleBuffer) {
        let arrival = HostClock.now()
        lastFrameAt = arrival
        fpsCounter.tick(at: arrival)

        // When was this frame captured? (Same clock as HostClock on the Mac.)
        // If the timestamp looks wrong we just don't use it for latency numbers.
        let captureTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let frameAge = arrival - captureTime
        let validCaptureTime: Double? = (captureTime.isFinite && frameAge >= 0 && frameAge < 1) ? captureTime : nil
        if validCaptureTime != nil {
            cameraDelays.add(frameAge * 1000)
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 1. Vision: find the face and its head angles.
        let result: TrackingResult
        do {
            result = try tracker.analyze(pixelBuffer)
            snapshot.visionError = nil
        } catch {
            result = .noFace
            snapshot.visionError = error.localizedDescription
        }
        visionTimes.add((HostClock.now() - arrival) * 1000)

        // 2. Calibration / gesture / safety.
        let timing = FrameTiming(arrival: arrival, capture: validCaptureTime)
        switch result {
        case .face(let measurement):
            handleFace(measurement, timing: timing)
        case .noFace:
            handleNoFace(at: arrival, anglesMissing: false)
        case .faceWithoutAngles:
            handleNoFace(at: arrival, anglesMissing: true)
        }

        processingTimes.add((HostClock.now() - arrival) * 1000)
        publish(force: false)
    }

    // MARK: - Per-frame logic

    private struct FrameTiming {
        let arrival: Double   // When the frame reached our code.
        let capture: Double?  // When the camera captured it (if known).
    }

    private func handleFace(_ measurement: FaceMeasurement, timing: FrameTiming) {
        let now = timing.arrival

        // After a long gap, start smoothing fresh instead of blending in old angles.
        if let last = lastFaceSeenAt, now - last > Config.Smoothing.resetAfterGap {
            filter.reset()
        }
        lastFaceSeenAt = now
        let smoothed = filter.filter(measurement.angles, at: now)

        snapshot.faceVisible = true
        snapshot.anglesMissing = false
        snapshot.faceConfidence = measurement.confidence
        snapshot.rawAngles = measurement.angles

        // While calibrating: just collect samples (key presses are blocked).
        if calibrator.isCollecting {
            if let result = calibrator.addSample(measurement.angles, at: now) {
                finishCalibration(result)
            } else {
                snapshot.calibration = .inProgress(progress: calibrator.progress, faceVisible: true)
            }
            return
        }

        guard let calibration = calibration else { return }

        // Everything is measured relative to your neutral position.
        let relative = smoothed - calibration.neutral
        snapshot.relativeAngles = relative

        // We assume tilting UP makes Vision's pitch go DOWN, so flip the sign to get
        // "degrees tilted up". Config.TiltUp.flipDirection reverses this.
        let tiltUpDegrees = Config.TiltUp.flipDirection ? relative.pitch : -relative.pitch
        snapshot.tiltUpDegrees = tiltUpDegrees

        runTiltUpGesture(value: tiltUpDegrees, timing: timing)
    }

    private func handleNoFace(at now: Double, anglesMissing: Bool) {
        snapshot.faceVisible = false
        snapshot.anglesMissing = anglesMissing
        snapshot.rawAngles = nil
        snapshot.relativeAngles = nil
        snapshot.tiltUpDegrees = nil

        if calibrator.isCollecting {
            calibrator.faceMissing()
            snapshot.calibration = .inProgress(progress: calibrator.progress, faceVisible: false)
        }

        // Never keep counting a hold time while we can't see the face.
        tiltUp.cancelHold()
        enforceFaceLostRule(now: now)
    }

    private func runTiltUpGesture(value: Double, timing: FrameTiming) {
        let key = Config.TiltUp.key

        // Presses are blocked (control off, calibrating, no permission, quitting):
        // keep the gesture disarmed so it needs a return to neutral afterwards.
        if keyboard.isBlocked {
            tiltUp.reset(requireNeutral: true)
            return
        }

        // If something else released our key (kill switch, safety), resync.
        if tiltUp.isActive && !keyboard.isHeld(key) {
            tiltUp.reset(requireNeutral: true)
        }

        guard let event = tiltUp.update(value: value, at: timing.arrival) else { return }

        switch event {
        case .press:
            if keyboard.press(key) {
                recordKeyEvent(timing: timing)
            } else {
                tiltUp.reset(requireNeutral: true)  // Press was refused (blocked).
            }
        case .release:
            keyboard.release(key)
            recordKeyEvent(timing: timing)
        }
        publish(force: true)
    }

    /// Latency = time from the camera capturing the frame to the key event being sent.
    /// (If the capture time is unknown, we measure from when the frame reached us.)
    private func recordKeyEvent(timing: FrameTiming) {
        let sentAt = HostClock.now()
        let latencyMs = (sentAt - (timing.capture ?? timing.arrival)) * 1000
        keyLatencies.add(latencyMs)
        snapshot.lastKeyLatencyMs = latencyMs
        snapshot.keyEventCount += 1
    }

    // MARK: - Calibration

    private func beginCalibration() {
        // Block (and release) keys while recording the neutral position.
        keyboard.setBlocked(.calibrating, true)
        tiltUp.reset(requireNeutral: true)
        calibrator.start()
        snapshot.calibration = .inProgress(progress: 0, faceVisible: snapshot.faceVisible)
        logEvent("Calibration started: look straight at the camera")
        publish(force: true)
    }

    private func finishCalibration(_ result: CalibrationResult) {
        calibration = result
        tiltUp.reset(requireNeutral: true)
        snapshot.calibration = .done(result)
        keyboard.setBlocked(.calibrating, false)
        logEvent(String(format: "Calibrated: neutral pitch %.1f°, jitter ±%.1f°",
                        result.neutral.pitch, result.pitchJitter))
        publish(force: true)
    }

    // MARK: - Safety

    /// If the face has been missing for longer than the timeout, release everything.
    private func enforceFaceLostRule(now: Double) {
        let missingFor = lastFaceSeenAt.map { now - $0 } ?? .infinity
        guard missingFor > Config.Safety.faceLostTimeout else { return }

        if keyboard.hasHeldKeys {
            keyboard.releaseAll()
            logEvent("Released \(Config.TiltUp.keyName): face lost for over \(Int(Config.Safety.faceLostTimeout * 1000)) ms")
            publish(force: true)
        }
        // When the face comes back, require a return to neutral before firing again.
        tiltUp.reset(requireNeutral: true)
    }

    /// The watchdog is a timer on the tracking queue. It catches the case where
    /// frames STOP arriving (camera unplugged, frozen, or taken by another app):
    /// then no frame code runs at all, so the per-frame checks can't help.
    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Config.Safety.watchdogInterval,
                       repeating: Config.Safety.watchdogInterval)
        timer.setEventHandler { [weak self] in
            self?.watchdogTick()
        }
        timer.resume()
        watchdog = timer
    }

    private func watchdogTick() {
        let now = HostClock.now()
        enforceFaceLostRule(now: now)

        // No frames for a while: update the window so it shows the camera stalled.
        if let lastFrame = lastFrameAt, now - lastFrame > 0.5 {
            snapshot.faceVisible = false
            snapshot.tiltUpDegrees = nil
            publish(force: false)
        } else if lastFrameAt == nil {
            publish(force: false)
        }
    }

    // MARK: - Publishing to the window

    private func logEvent(_ text: String) {
        let line = "\(Self.timeFormatter.string(from: Date()))  \(text)"
        snapshot.recentEvents.insert(line, at: 0)
        if snapshot.recentEvents.count > 6 {
            snapshot.recentEvents.removeLast(snapshot.recentEvents.count - 6)
        }
    }

    /// Sends a copy of the state to the window, at most ~30 times a second
    /// (unless `force`, used for important changes like a key press).
    private func publish(force: Bool) {
        let now = HostClock.now()
        guard force || now - lastPublishAt >= Config.UI.refreshInterval else { return }
        lastPublishAt = now

        snapshot.gesturePhase = tiltUp.phase
        snapshot.keyHeld = keyboard.isHeld(Config.TiltUp.key)
        snapshot.blockReasons = keyboard.currentBlockReasons
        snapshot.cameraFPS = fpsCounter.rate
        snapshot.droppedFrames = droppedFrames
        snapshot.secondsSinceLastFrame = lastFrameAt.map { now - $0 }
        snapshot.visionMs = visionTimes.average
        snapshot.processingMs = processingTimes.average
        snapshot.processingMaxMs = processingTimes.maximum
        snapshot.cameraDelayMs = cameraDelays.average
        snapshot.averageKeyLatencyMs = keyLatencies.average

        onSnapshot?(snapshot)
    }
}
