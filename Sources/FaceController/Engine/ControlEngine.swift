import CoreMedia
import CoreVideo
import Foundation

/// The tight loop: camera frame -> Vision -> smoothing -> gestures -> keys / mouse.
///
/// THREADING (the tricky part, in plain language):
/// Everything in this class runs on ONE background queue, `queue`. The camera
/// delivers frames straight onto it, the safety watchdog runs on it, and the
/// public methods (recalibrate, setMode, etc.) hop onto it with `queue.async`.
/// Because only one thing ever runs on that queue at a time, the engine's
/// variables can't be changed by two threads at once, so no locks are needed here.
/// The window never touches these variables; it only receives copies (snapshots).
///
/// There's no waiting anywhere in the loop: each frame is processed the moment it
/// arrives and key events are sent from the same function call. (Mouse movement is
/// sent by AimController's own 120 Hz timer, using the speed we set here.)
final class ControlEngine {

    /// High priority ("user interactive") because latency matters.
    let queue = DispatchQueue(label: "FaceController.tracking", qos: .userInteractive)

    /// Called on `queue` with a fresh copy of the state (about 30 times a second).
    var onSnapshot: ((EngineSnapshot) -> Void)?

    private let input: VirtualInput
    private let aim: AimController
    private let tracker = HeadPoseTracker()
    private var angleFilter = HeadAnglesFilter()
    private var expressionFilter = ExpressionFilter()
    private var calibrator = Calibrator()
    private var calibration: CalibrationResult?

    private var mode: ControlMode = Config.Mapping.startMode
    /// One detector per gesture (thresholds depend on the mode).
    private var gestures: [GestureID: ThresholdGesture] = [:]
    /// Latest value of every gesture (relative to neutral), for the debug window.
    private var latestValues: [GestureID: Double] = [:]
    private var lastTapAt: [GestureID: Double] = [:]
    /// Snake mode: after a turn, nothing fires until the head is back in the center.
    private var snakeWaitingForCenter = true
    private var framesMirrored = false
    private var aimState = AimState()

    private var lastFaceSeenAt: Double?
    private var lastExpressionsAt: Double?
    private var lastFrameAt: Double?
    private var watchdog: DispatchSourceTimer?

    private var snapshot = EngineSnapshot()
    private var lastPublishAt: Double = 0

    // Performance measurements.
    private var fpsCounter = RateCounter()
    private var visionTimes = RollingAverage()
    private var landmarksTimes = RollingAverage()
    private var processingTimes = RollingAverage()
    private var cameraDelays = RollingAverage()
    private var outputLatencies = RollingAverage()
    private var droppedFrames = 0

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let headDirections: [GestureID] = [.tiltUp, .tiltDown, .turnLeft, .turnRight]

    init(input: VirtualInput, aim: AimController) {
        self.input = input
        self.aim = aim
        gestures = Self.makeGestures(for: mode)
    }

    // MARK: - Public (safe to call from any thread)

    /// Starts the first calibration and the safety watchdog.
    func start() {
        queue.async {
            self.aim.setActive(self.mode.headMovesMouse)
            self.beginCalibration()
            self.startWatchdog()
        }
    }

    /// Records a new neutral face (the C key / Recalibrate button).
    func recalibrate() {
        queue.async { self.beginCalibration() }
    }

    /// Call after control is turned on or off. VirtualInput has already released
    /// everything; this makes every gesture wait for neutral before firing again.
    func controlWasToggled(isOn: Bool) {
        queue.async {
            self.resetAllGestures(requireNeutral: true)
            self.aim.stopMoving()
            self.logEvent(isOn ? "Control turned ON" : "Control turned OFF (everything released)")
            self.publish(force: true)
        }
    }

    /// Switches between Keys, Aim and Snake. Releases everything first.
    func setMode(_ newMode: ControlMode) {
        queue.async {
            guard newMode != self.mode else { return }
            self.mode = newMode
            self.input.releaseAll()
            self.aim.setActive(newMode.headMovesMouse)
            self.aimState = AimState()
            self.gestures = Self.makeGestures(for: newMode)
            self.lastTapAt.removeAll()
            self.snakeWaitingForCenter = true
            self.logEvent("Mode: \(newMode.title) (everything released)")
            self.publish(force: true)
        }
    }

    /// Tells the engine whether the camera frames are mirrored (see PlayerDirections).
    func setFramesMirrored(_ mirrored: Bool) {
        queue.async { self.framesMirrored = mirrored }
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

        // 1. Vision: find the face, its head angles and its expressions.
        let result: TrackingResult
        do {
            result = try tracker.analyze(pixelBuffer)
            snapshot.visionError = nil
        } catch {
            result = .noFace
            snapshot.visionError = error.localizedDescription
        }
        visionTimes.add((HostClock.now() - arrival) * 1000)
        if let landmarks = tracker.lastLandmarksDuration {
            landmarksTimes.add(landmarks * 1000)
        }

        // 2. Calibration / gestures / aiming / safety.
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

        // After a long gap, start smoothing fresh instead of blending in old values.
        if let last = lastFaceSeenAt, now - last > Config.Smoothing.resetAfterGap {
            angleFilter.reset()
        }
        lastFaceSeenAt = now
        let smoothedAngles = angleFilter.filter(measurement.angles, at: now)

        var smoothedExpressions: ExpressionValues?
        if let expressions = measurement.expressions {
            if let last = lastExpressionsAt, now - last > Config.Smoothing.resetAfterGap {
                expressionFilter.reset()
            }
            lastExpressionsAt = now
            smoothedExpressions = expressionFilter.filter(expressions, at: now)
        }

        snapshot.faceVisible = true
        snapshot.anglesMissing = false
        snapshot.faceConfidence = measurement.confidence
        snapshot.rawAngles = measurement.angles
        snapshot.expressions = smoothedExpressions

        // While calibrating: just collect samples (input is blocked).
        if calibrator.isCollecting {
            if let result = calibrator.addSample(measurement.angles,
                                                 expressions: measurement.expressions,
                                                 at: now) {
                finishCalibration(result)
            } else {
                snapshot.calibration = .inProgress(progress: calibrator.progress, faceVisible: true)
            }
            return
        }

        guard let calibration = calibration else { return }

        // Everything is measured relative to your neutral face, from YOUR point of view.
        let relative = smoothedAngles - calibration.neutral
        let offset = PlayerDirections.offset(relative: relative, framesMirrored: framesMirrored)
        snapshot.relativeAngles = relative
        snapshot.playerOffset = offset

        var values: [GestureID: Double] = [
            .tiltUp: offset.up,
            .tiltDown: -offset.up,
            .turnLeft: offset.left,
            .turnRight: -offset.left,
        ]
        if let expressions = smoothedExpressions, let neutral = calibration.neutralExpressions {
            values[.mouthOpen] = expressions.mouthOpen - neutral.mouthOpen
            values[.eyebrowsRaise] = expressions.browHeight - neutral.browHeight
        }
        latestValues = values

        enforceExpressionLostRule(now: now)

        // Input blocked (control off, calibrating, no permission, quitting): keep
        // every gesture disarmed so each needs a return to neutral afterwards.
        if input.isBlocked {
            resetAllGestures(requireNeutral: true)
            aim.stopMoving()
            aimState = AimState(active: mode.headMovesMouse, sensitivity: aim.currentSensitivity)
            return
        }

        switch mode {
        case .keys, .aim:
            runHoldGestures(values: values, timing: timing)
        case .snake:
            runSnake(values: values, timing: timing)
        }

        if mode.headMovesMouse {
            aimState = aim.update(offset: offset, at: now)
        }
    }

    private func handleNoFace(at now: Double, anglesMissing: Bool) {
        snapshot.faceVisible = false
        snapshot.anglesMissing = anglesMissing
        snapshot.rawAngles = nil
        snapshot.relativeAngles = nil
        snapshot.playerOffset = nil
        snapshot.expressions = nil
        latestValues = [:]

        if calibrator.isCollecting {
            calibrator.faceMissing()
            snapshot.calibration = .inProgress(progress: calibrator.progress, faceVisible: false)
        }

        // Never keep counting a hold time, or keep the pointer moving, without a face.
        for gesture in GestureID.allCases {
            gestures[gesture]?.cancelHold()
        }
        aim.stopMoving()
        aimState.speedX = 0
        aimState.speedY = 0
        enforceFaceLostRule(now: now)
    }

    /// Keys and Aim modes: each gesture holds (or taps) its key/button.
    private func runHoldGestures(values: [GestureID: Double], timing: FrameTiming) {
        let now = timing.arrival
        var changed = false

        for gesture in GestureID.allCases {
            guard let binding = mode.bindings[gesture], var detector = gestures[gesture] else { continue }
            defer { gestures[gesture] = detector }

            guard let value = values[gesture] else {
                detector.cancelHold()  // Not measured this frame (e.g. landmarks missing).
                continue
            }

            // If something else released our key (kill switch, safety), resync.
            if binding.style == .hold && detector.isActive && !input.isHeld(binding.action) {
                detector.reset(requireNeutral: true)
            }

            guard let event = detector.update(value: value, at: now) else { continue }
            changed = true

            switch event {
            case .press:
                let sent = binding.style == .tap
                    ? input.tap(binding.action, duration: Config.Snake.tapDuration)
                    : input.press(binding.action)
                if sent {
                    recordOutputEvent(timing: timing)
                    if binding.style == .tap { lastTapAt[gesture] = now }
                } else {
                    detector.reset(requireNeutral: true)  // Refused (blocked).
                }
            case .release:
                if binding.style == .hold {
                    input.release(binding.action)
                    recordOutputEvent(timing: timing)
                }
            }
        }

        if changed { publish(force: true) }
    }

    /// Snake mode: one arrow-key TAP per head movement, then wait for the center.
    private func runSnake(values: [GestureID: Double], timing: FrameTiming) {
        let now = timing.arrival
        let directions = Self.headDirections

        if snakeWaitingForCenter {
            // "Center" = within neutralDegrees of neutral on BOTH axes.
            let centered = directions.allSatisfy { abs(values[$0] ?? .infinity) < Config.Snake.neutralDegrees }
            guard centered else { return }
            snakeWaitingForCenter = false
            for direction in directions {
                gestures[direction]?.reset(requireNeutral: false)
            }
            publish(force: true)
        }

        for direction in directions {
            guard let binding = mode.bindings[direction],
                  let value = values[direction],
                  gestures[direction]?.update(value: value, at: now) == .press else { continue }

            if input.tap(binding.action, duration: Config.Snake.tapDuration) {
                recordOutputEvent(timing: timing)
                lastTapAt[direction] = now
            }
            // One turn per head movement: everything waits until the head is centered.
            snakeWaitingForCenter = true
            for other in directions {
                gestures[other]?.reset(requireNeutral: true)
            }
            publish(force: true)
            return
        }
    }

    /// Latency = time from the camera capturing the frame to the event being sent.
    /// (If the capture time is unknown, we measure from when the frame reached us.)
    private func recordOutputEvent(timing: FrameTiming) {
        let sentAt = HostClock.now()
        let latencyMs = (sentAt - (timing.capture ?? timing.arrival)) * 1000
        outputLatencies.add(latencyMs)
        snapshot.lastOutputLatencyMs = latencyMs
        snapshot.outputEventCount += 1
    }

    private static func makeGestures(for mode: ControlMode) -> [GestureID: ThresholdGesture] {
        var result: [GestureID: ThresholdGesture] = [:]
        for gesture in GestureID.allCases {
            let thresholds = mode.thresholds(for: gesture)
            result[gesture] = ThresholdGesture(pressThreshold: thresholds.press,
                                               releaseThreshold: thresholds.release,
                                               holdTime: thresholds.holdTime)
        }
        return result
    }

    private func resetAllGestures(requireNeutral: Bool) {
        for gesture in GestureID.allCases {
            gestures[gesture]?.reset(requireNeutral: requireNeutral)
        }
        snakeWaitingForCenter = true
    }

    // MARK: - Calibration

    private func beginCalibration() {
        // Block (and release) everything while recording the neutral face.
        input.setBlocked(.calibrating, true)
        aim.stopMoving()
        resetAllGestures(requireNeutral: true)
        calibrator.start()
        snapshot.calibration = .inProgress(progress: 0, faceVisible: snapshot.faceVisible)
        logEvent("Calibration started: look straight at the camera, face relaxed")
        publish(force: true)
    }

    private func finishCalibration(_ result: CalibrationResult) {
        calibration = result
        resetAllGestures(requireNeutral: true)
        snapshot.calibration = .done(result)
        input.setBlocked(.calibrating, false)
        if result.neutralExpressions == nil {
            logEvent("Calibrated head, but couldn't read mouth/eyebrows (expressions off)")
        } else {
            logEvent("Calibrated: head + mouth + eyebrows")
        }
        publish(force: true)
    }

    // MARK: - Safety

    /// If the face has been missing for longer than the timeout, release everything.
    private func enforceFaceLostRule(now: Double) {
        let missingFor = lastFaceSeenAt.map { now - $0 } ?? .infinity
        guard missingFor > Config.Safety.faceLostTimeout else { return }

        aim.stopMoving()
        if input.hasHeldOutputs {
            input.releaseAll()
            logEvent("Released everything: face lost for over \(Int(Config.Safety.faceLostTimeout * 1000)) ms")
            publish(force: true)
        }
        // When the face comes back, require a return to neutral before firing again.
        resetAllGestures(requireNeutral: true)
    }

    /// Same rule for expressions: if the mouth/eyebrows can't be read for longer than
    /// the timeout (while the head still can), release what they hold.
    private func enforceExpressionLostRule(now: Double) {
        let missingFor = lastExpressionsAt.map { now - $0 } ?? .infinity
        guard missingFor > Config.Safety.faceLostTimeout else { return }

        for gesture in GestureID.allCases where !gesture.isHeadGesture {
            if let binding = mode.bindings[gesture], input.isHeld(binding.action) {
                input.release(binding.action)
                logEvent("Released \(binding.label): mouth/eyebrows not readable")
            }
            gestures[gesture]?.reset(requireNeutral: true)
        }
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
            snapshot.playerOffset = nil
            latestValues = [:]
            publish(force: false)
        } else if lastFrameAt == nil {
            publish(force: false)
        }
    }

    // MARK: - Publishing to the window

    private func logEvent(_ text: String) {
        let line = "\(Self.timeFormatter.string(from: Date()))  \(text)"
        snapshot.recentEvents.insert(line, at: 0)
        if snapshot.recentEvents.count > 8 {
            snapshot.recentEvents.removeLast(snapshot.recentEvents.count - 8)
        }
    }

    /// Sends a copy of the state to the window, at most ~30 times a second
    /// (unless `force`, used for important changes like a key press).
    private func publish(force: Bool) {
        let now = HostClock.now()
        guard force || now - lastPublishAt >= Config.UI.refreshInterval else { return }
        lastPublishAt = now

        snapshot.mode = mode
        snapshot.framesMirrored = framesMirrored
        snapshot.snakeWaitingForCenter = mode == .snake && snakeWaitingForCenter
        snapshot.aim = mode.headMovesMouse ? aimState : AimState(sensitivity: aim.currentSensitivity)
        snapshot.gestures = GestureID.allCases.map { gesture in
            let binding = mode.bindings[gesture]
            var firing = false
            if let binding = binding {
                switch binding.style {
                case .hold:
                    firing = input.isHeld(binding.action)
                case .tap:
                    firing = lastTapAt[gesture].map { now - $0 < Config.UI.tapFlashDuration } ?? false
                }
            }
            return GestureSnapshot(gesture: gesture,
                                   value: latestValues[gesture],
                                   thresholds: mode.thresholds(for: gesture),
                                   binding: binding,
                                   phase: gestures[gesture]?.phase ?? .ready,
                                   firing: firing)
        }
        snapshot.blockReasons = input.currentBlockReasons
        snapshot.cameraFPS = fpsCounter.rate
        snapshot.droppedFrames = droppedFrames
        snapshot.secondsSinceLastFrame = lastFrameAt.map { now - $0 }
        snapshot.visionMs = visionTimes.average
        snapshot.landmarksMs = landmarksTimes.average
        snapshot.processingMs = processingTimes.average
        snapshot.processingMaxMs = processingTimes.maximum
        snapshot.cameraDelayMs = cameraDelays.average
        snapshot.averageOutputLatencyMs = outputLatencies.average

        onSnapshot?(snapshot)
    }
}
