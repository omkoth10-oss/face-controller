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
    /// Called on `queue` when Minecraft option 2 switches the head's job (for the sound).
    var onHeadJobSwitch: ((HeadJob) -> Void)?

    private let input: VirtualInput
    private let aim: AimController
    private let tracker = HeadPoseTracker()
    private var angleFilter = HeadAnglesFilter()
    private var expressionFilter = ExpressionFilter()
    private var calibrator = Calibrator()
    private var calibration: CalibrationResult?

    private var mode: ControlMode = Config.Mapping.startMode
    /// What every gesture does right now: the mode's bindings, or in Minecraft the
    /// head option's (and option 2's current MOVE/AIM job). Set by refreshBindings().
    private var bindings: [GestureID: OutputBinding] = [:]
    /// One detector per gesture (thresholds depend on the mode).
    private var gestures: [GestureID: ThresholdGesture] = [:]
    /// Latest value of every gesture (relative to neutral), for the debug window.
    private var latestValues: [GestureID: Double] = [:]
    private var lastTapAt: [GestureID: Double] = [:]
    /// Neutral head angles (the CENTER): set by calibration, then moved by Recenter
    /// and by the floating center. `neutralAnchor` is where it was last set on purpose
    /// (calibration or recenter), so we can show how far the center has floated.
    private var neutralAngles: HeadAngles?
    private var neutralAnchor: HeadAngles?
    private var lastSmoothedAngles: HeadAngles?

    // Snake mode (see SnakeController.swift).
    private var snake = SnakeController(settings: SnakeSettings())
    /// Snake's own, lighter smoothing (the Smoothing slider).
    private var snakeFilter = OffsetFilter()
    private var snakeStatus = SnakeStatus()
    private var snakeLatencies = RollingAverage()
    private var lastSnakeTurnAt: Double?
    /// When the last Snake tap was (or is scheduled to be) sent, for spacing taps.
    private var lastSnakeTapSlot = -Double.infinity
    /// Turn log line of each direction's latest turn, to add "head went to N°" later.
    private var snakeTurnLogIds: [GestureID: Int] = [:]
    private var turnLogCounter = 0
    /// Snake: an attempted turn while input is blocked was already logged.
    private var blockedByInputLogged = false

    // Floating center (see FloatingCenter.swift).
    private var floatingCenter = FloatingCenter()
    private var floatingSettings = FloatingCenterSettings()
    /// When a HEAD direction last fired or released; the center waits a moment after.
    private var lastHeadOutputAt = -Double.infinity
    private var framesMirrored = false
    private var aimState = AimState()

    // Minecraft preset (see HeadOptions.swift).
    private var minecraft = MinecraftSettings()
    /// Option 2's tilt-to-switch gesture and the head's current job (MOVE / AIM).
    private var headSwitch = HeadJobSwitch(tiltDegrees: Config.Minecraft.defaultSwitchTiltDegrees)
    /// True while the head is tilted toward a shoulder (switching): its moving and
    /// aiming pause so the switch gesture can't walk or turn the camera.
    private var headPaused = false
    private var latestTilt: Double?

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

    /// With milliseconds, for the Turn log.
    private static let preciseTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    init(input: VirtualInput, aim: AimController) {
        self.input = input
        self.aim = aim
        refreshBindings()
    }

    // MARK: - Public (safe to call from any thread)

    /// Starts the first calibration and the safety watchdog.
    func start() {
        queue.async {
            self.aim.setActive(self.mode.usesAim)
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
            self.aim.setActive(newMode.usesAim)
            self.aimState = AimState()
            self.headSwitch = HeadJobSwitch(tiltDegrees: self.minecraft.switchTiltDegrees)
            self.headPaused = false
            self.refreshBindings()
            self.lastTapAt.removeAll()
            self.snake.requireReturn()
            self.snakeFilter.reset()
            self.floatingCenter.reset()
            self.logEvent("Mode: \(newMode.title) (everything released)")
            self.publish(force: true)
        }
    }

    /// Tells the engine whether the camera frames are mirrored (see PlayerDirections).
    func setFramesMirrored(_ mirrored: Bool) {
        queue.async { self.framesMirrored = mirrored }
    }

    /// New values from the Snake sliders.
    func setSnakeSettings(_ settings: SnakeSettings) {
        queue.async {
            let smoothingWasOff = self.snake.settings.smoothingCutoff == nil
            self.snake.settings = settings
            if smoothingWasOff && settings.smoothingCutoff != nil {
                self.snakeFilter.reset()  // Don't blend in stale values when turning smoothing on.
            }
            self.publish(force: true)
        }
    }

    /// New Minecraft preset settings (head option, its sliders, overlay).
    /// A new option or walk threshold releases everything and starts the head fresh.
    func setMinecraftSettings(_ settings: MinecraftSettings) {
        queue.async {
            let old = self.minecraft
            self.minecraft = settings
            if settings.switchTiltDegrees != old.switchTiltDegrees {
                self.headSwitch.setTiltDegrees(settings.switchTiltDegrees)
            }
            guard self.mode == .minecraft else { return }
            let optionChanged = settings.option != old.option
            let walkChanged = settings.moveDegrees != old.moveDegrees
                || settings.walkZoneDegrees != old.walkZoneDegrees
            if optionChanged {
                self.headSwitch = HeadJobSwitch(tiltDegrees: settings.switchTiltDegrees)
            }
            if optionChanged || walkChanged {
                self.input.releaseAll()
                self.aim.stopMoving()
                self.aimState = AimState(sensitivity: self.aim.currentSensitivity)
                self.headPaused = false
                self.refreshBindings()
                self.floatingCenter.reset()
                if optionChanged {
                    self.logEvent("Minecraft: \(settings.option.title) (everything released)")
                }
            }
            self.publish(force: true)
        }
    }

    /// Option 2's "Switch now" button: flips MOVE ↔ AIM without the gesture.
    func toggleHeadJob() {
        queue.async {
            guard self.mode == .minecraft, self.minecraft.option == .modeSwitch else { return }
            self.headSwitch.toggle()
            self.headJobDidSwitch(now: HostClock.now(), how: "Switch button")
        }
    }

    /// New Floating center settings (per-mode on/off, follow time).
    func setFloatingCenterSettings(_ settings: FloatingCenterSettings) {
        queue.async {
            self.floatingSettings = settings
            self.floatingCenter.reset()
            self.publish(force: true)
        }
    }

    /// RECENTER: "where my head is right now" becomes neutral, instantly.
    /// (Calibration takes 3 seconds and also re-measures the mouth/eyebrows;
    /// recenter only moves the head's neutral.) Releases everything first.
    func recenter() {
        queue.async {
            guard self.calibration != nil, !self.calibrator.isCollecting,
                  self.snapshot.faceVisible, let current = self.lastSmoothedAngles else {
                self.logEvent("Can't recenter: no face, or not calibrated yet")
                self.publish(force: true)
                return
            }
            self.input.releaseAll()
            self.aim.stopMoving()
            self.neutralAngles = current
            self.neutralAnchor = current
            self.snakeFilter.reset()
            self.floatingCenter.reset()
            self.resetAllGestures(requireNeutral: true)
            self.snake.arm()  // Your head IS the center now, so Snake is ready at once.
            self.logEvent("Recentered: where your head is now is the new neutral")
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

        // 1. Vision: find the face, its head angles and its expressions.
        let result: TrackingResult
        do {
            // Snake doesn't use the mouth/eyebrows, so skip that step for speed
            // (but always read them while calibrating, for the other modes).
            let wantExpressions = mode != .snake || calibrator.isCollecting
            result = try tracker.analyze(pixelBuffer, readExpressions: wantExpressions)
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
            snakeFilter.reset()
        }
        lastFaceSeenAt = now
        let smoothedAngles = angleFilter.filter(measurement.angles, at: now)
        lastSmoothedAngles = smoothedAngles

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

        guard let calibration = calibration, let neutral = neutralAngles else { return }

        // Everything is measured relative to your neutral face, from YOUR point of view.
        let relative = smoothedAngles - neutral
        var offset = PlayerDirections.offset(relative: relative, framesMirrored: framesMirrored)
        if mode == .snake {
            // Snake uses the raw angles with its own, lighter smoothing (Smoothing slider),
            // because every millisecond of smoothing delay makes turns feel late.
            let rawOffset = PlayerDirections.offset(relative: measurement.angles - neutral,
                                                    framesMirrored: framesMirrored)
            offset = snakeFilter.filter(rawOffset, at: now, cutoff: snake.settings.smoothingCutoff)
        }
        snapshot.relativeAngles = relative
        snapshot.playerOffset = offset
        let tilt = PlayerDirections.shoulderTilt(relative: relative)
        latestTilt = tilt

        var values: [GestureID: Double] = [
            .tiltUp: offset.up,
            .tiltDown: -offset.up,
            .turnLeft: offset.left,
            .turnRight: -offset.left,
        ]
        if let expressions = smoothedExpressions, let neutralFace = calibration.neutralExpressions {
            values[.mouthOpen] = expressions.mouthOpen - neutralFace.mouthOpen
            values[.eyebrowsRaise] = expressions.browHeight - neutralFace.browHeight
        }
        latestValues = values

        enforceExpressionLostRule(now: now)

        // Input blocked (control off, calibrating, no permission, quitting): keep
        // every gesture disarmed so each needs a return to neutral afterwards.
        if input.isBlocked {
            resetAllGestures(requireNeutral: true)
            aim.stopMoving()
            headPaused = false
            aimState = AimState(active: headAimsNow, sensitivity: aim.currentSensitivity)
            floatingCenter.markOff("paused: \(input.currentBlockReasons.first?.rawValue ?? "input blocked")")
            if mode == .snake { logSnakeAttemptWhileBlocked(offset) }
            return
        }
        blockedByInputLogged = false

        switch mode {
        case .keys:
            runHoldGestures(values: values, timing: timing)
        case .aim:
            runHoldGestures(values: values, timing: timing)
            aimState = aim.update(offset: offset, at: now)
        case .snake:
            runSnake(offset: offset, timing: timing)
        case .minecraft:
            runMinecraft(values: values, offset: offset, tilt: tilt, timing: timing)
        }

        // Last: let the center follow your head if it's resting (never while busy).
        updateFloatingCenter(offset: offset, smoothedAngles: smoothedAngles, now: now)
    }

    private func handleNoFace(at now: Double, anglesMissing: Bool) {
        snapshot.faceVisible = false
        snapshot.anglesMissing = anglesMissing
        snapshot.rawAngles = nil
        snapshot.relativeAngles = nil
        snapshot.playerOffset = nil
        snapshot.expressions = nil
        latestValues = [:]
        latestTilt = nil

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
        floatingCenter.reset()
        enforceFaceLostRule(now: now)
    }

    /// Keys and Aim modes: each gesture holds (or taps) its key/button.
    private func runHoldGestures(values: [GestureID: Double], timing: FrameTiming) {
        let now = timing.arrival
        var changed = false

        for gesture in GestureID.allCases {
            guard let binding = bindings[gesture], var detector = gestures[gesture] else { continue }
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
            if gesture.isHeadGesture { lastHeadOutputAt = now }

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

    /// Minecraft preset: who walks and who aims depends on the head option
    /// (HeadOptions.swift). The face's actions run the same way in every option.
    private func runMinecraft(values: [GestureID: Double], offset: PlayerHeadOffset,
                              tilt: Double, timing: FrameTiming) {
        let now = timing.arrival
        var gestureValues = values
        headPaused = false

        if minecraft.option == .modeSwitch {
            if headSwitch.update(tilt: tilt, at: now) {
                headJobDidSwitch(now: now, how: "head tilted toward a shoulder")
            }
            // Tilting to switch: pause the head's walking and aiming, so the switch
            // gesture itself can't walk or turn the camera.
            if headSwitch.isTilting {
                headPaused = true
                releaseHeadKeys()
                for gesture in GestureID.allCases where gesture.isHeadGesture {
                    gestureValues[gesture] = nil
                }
            }
        }

        // Head walk keys (options 2 in MOVE and 3) and the face's actions.
        runHoldGestures(values: gestureValues, timing: timing)

        // Head aiming (options 1 and 3 always, option 2 in AIM).
        if headAimsNow && !headPaused {
            aimState = aim.update(offset: offset, at: now)
        } else {
            aim.stopMoving()
            aimState = AimState(active: false, sensitivity: aim.currentSensitivity)
        }
    }

    /// Option 2 just switched MOVE ↔ AIM: let go of everything, start the new job fresh,
    /// and tell the app (sound + overlay).
    private func headJobDidSwitch(now: Double, how: String) {
        input.releaseAll()
        aim.stopMoving()
        aimState = AimState(sensitivity: aim.currentSensitivity)
        refreshBindings()
        lastHeadOutputAt = now
        floatingCenter.reset()
        let job = headSwitch.job
        logEvent("Head job: \(job.title) (\(how); everything released)")
        onHeadJobSwitch?(job)
        publish(force: true)
    }

    /// Lets go of the head's keys (e.g. W A S D) and makes them wait for neutral.
    private func releaseHeadKeys() {
        for gesture in GestureID.allCases where gesture.isHeadGesture {
            if let binding = bindings[gesture], binding.style == .hold, input.isHeld(binding.action) {
                input.release(binding.action)
                lastHeadOutputAt = HostClock.now()
            }
            gestures[gesture]?.reset(requireNeutral: true)
        }
    }

    /// Does the head move the mouse right now?
    private var headAimsNow: Bool {
        switch mode {
        case .aim: return true
        case .minecraft: return minecraft.headAims(job: headSwitch.job)
        case .keys, .snake: return false
        }
    }

    /// Snake mode: one arrow-key TAP per turn. The rules live in SnakeController.
    private func runSnake(offset: PlayerHeadOffset, timing: FrameTiming) {
        let result = snake.update(offset: offset, at: timing.arrival)

        for blocked in result.blocked {
            let name = SnakeController.name(of: blocked.gesture)
            if blocked.isExtraTurn {
                snakeStatus.ignoredExtraCount += 1
                addTurnLog("\(name) IGNORED as an extra turn: \(blocked.reason)",
                           fired: false, latencyMs: nil, ignoredExtra: true)
            } else {
                snakeStatus.blockedCount += 1
                addTurnLog("\(name) BLOCKED: \(blocked.reason)", fired: false, latencyMs: nil)
            }
        }
        for settled in result.settled {
            noteTurnReach(settled)
        }
        for turn in result.turns {
            scheduleSnakeTurn(turn, timing: timing)
        }
        if !result.turns.isEmpty || !result.blocked.isEmpty || !result.settled.isEmpty {
            publish(force: true)
        }
    }

    /// SPACING, not dropping: if a turn comes less than "min time between turns"
    /// after the previous one, it's sent a few milliseconds LATER instead of being
    /// thrown away. So "left, then immediately up" always arrives as two key presses.
    private func scheduleSnakeTurn(_ turn: SnakeTurn, timing: FrameTiming) {
        let now = HostClock.now()
        let slot = max(now, lastSnakeTapSlot + snake.settings.minTurnInterval)
        lastSnakeTapSlot = slot
        lastHeadOutputAt = timing.arrival  // Floating center waits after turns.

        let delay = slot - now
        if delay <= 0.001 {
            sendSnakeTurn(turn, timing: timing, delay: 0)
        } else {
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.sendSnakeTurn(turn, timing: timing, delay: delay)
            }
        }
    }

    /// Actually taps the arrow key (runs on the tracking queue).
    private func sendSnakeTurn(_ turn: SnakeTurn, timing: FrameTiming, delay: Double) {
        let name = SnakeController.name(of: turn.gesture)
        guard mode == .snake, let binding = bindings[turn.gesture] else {
            addTurnLog("\(name) NOT SENT: left Snake mode", fired: false, latencyMs: nil)
            return
        }
        if input.tap(binding.action, duration: Config.Snake.tapDuration) {
            recordOutputEvent(timing: timing)
            let latency = snapshot.lastOutputLatencyMs
            if let latency = latency {
                snakeLatencies.add(latency)
                snakeStatus.lastTurnLatencyMs = latency
            }
            let now = HostClock.now()
            lastTapAt[turn.gesture] = now
            lastSnakeTurnAt = now
            snakeStatus.turnCount += 1
            if turn.viaFlick { snakeStatus.flickTurnCount += 1 }
            var how = turn.viaFlick ? "by flick (\(Int(turn.speed))°/s)" : "by position"
            if let note = turn.note {
                how += ", \(note)"
            }
            if delay > 0 {
                how += String(format: ", sent %.0f ms later to space it from the previous turn", delay * 1000)
            }
            snakeStatus.lastTurn = "\(name) \(how)"
            addTurnLog("\(name) \(how)", fired: true, latencyMs: latency)
            snakeTurnLogIds[turn.gesture] = turnLogCounter
        } else {
            let reason = input.currentBlockReasons.first?.rawValue ?? "input blocked"
            snakeStatus.blockedCount += 1
            addTurnLog("\(name) NOT SENT: \(reason)", fired: false, latencyMs: nil)
        }
        publish(force: true)
    }

    /// While input is blocked (e.g. control OFF), log ONE line when you try to turn,
    /// so a "dead" game is easy to explain.
    private func logSnakeAttemptWhileBlocked(_ offset: PlayerHeadOffset) {
        let press = snake.settings.pressDegrees
        let biggest = max(abs(offset.left), abs(offset.up))
        if biggest >= press, !blockedByInputLogged {
            blockedByInputLogged = true
            let gesture: GestureID = abs(offset.left) >= abs(offset.up)
                ? (offset.left > 0 ? .turnLeft : .turnRight)
                : (offset.up > 0 ? .tiltUp : .tiltDown)
            let reason = input.currentBlockReasons.first?.rawValue ?? "input blocked"
            snakeStatus.blockedCount += 1
            addTurnLog("\(SnakeController.name(of: gesture)) ignored: \(reason)", fired: false, latencyMs: nil)
            publish(force: true)
        } else if biggest < snake.settings.rearmDegrees {
            blockedByInputLogged = false
        }
    }

    /// A turn's movement is over: add how far the head went to its Turn log line.
    /// (Real turns usually go well past the press threshold; extra ones barely make it.)
    private func noteTurnReach(_ settled: SnakeSettledTurn) {
        guard let id = snakeTurnLogIds.removeValue(forKey: settled.gesture),
              let index = snakeStatus.turnLog.firstIndex(where: { $0.id == id }) else { return }
        snakeStatus.turnLog[index].reachedDegrees = settled.peakDegrees
    }

    private func addTurnLog(_ text: String, fired: Bool, latencyMs: Double?, ignoredExtra: Bool = false) {
        turnLogCounter += 1
        let entry = TurnLogEntry(id: turnLogCounter,
                                 time: Self.preciseTimeFormatter.string(from: Date()),
                                 text: text,
                                 fired: fired,
                                 latencyMs: latencyMs,
                                 ignoredExtra: ignoredExtra)
        snakeStatus.turnLog.insert(entry, at: 0)
        if snakeStatus.turnLog.count > Config.Snake.turnLogLength {
            snakeStatus.turnLog.removeLast(snakeStatus.turnLog.count - Config.Snake.turnLogLength)
        }
    }

    // MARK: - Floating center

    private func updateFloatingCenter(offset: PlayerHeadOffset, smoothedAngles: HeadAngles, now: Double) {
        guard floatingSettings.isEnabled(for: mode) else {
            floatingCenter.markOff("off in \(mode.title) mode")
            return
        }
        guard var neutral = neutralAngles else { return }
        floatingCenter.update(neutral: &neutral,
                              head: smoothedAngles,
                              offset: offset,
                              zone: floatingCenterZone(),
                              busyReason: floatingCenterBusyReason(now: now),
                              followTime: floatingSettings.followTime,
                              at: now)
        neutralAngles = neutral
    }

    /// How close to the center counts as "resting near center" in this mode.
    /// Always well inside where anything fires, so moving the center can't trigger.
    private func floatingCenterZone() -> Double {
        switch mode {
        case .keys:
            return headKeyZone()
        case .aim:
            // Inside the deadzone, so the pointer never moves while the center follows.
            return min(Config.Aim.horizontalDeadzone, Config.Aim.verticalDeadzone)
        case .snake:
            // Stricter than the re-arm zone: only a head that's really back at center.
            return snake.settings.rearmDegrees * Config.FloatingCenter.snakeZoneFraction
        case .minecraft:
            // Aiming: inside the deadzone (option 3's walk zone is further out still).
            // Option 2 in MOVE: like Keys mode.
            if headAimsNow {
                return min(Config.Aim.horizontalDeadzone, Config.Aim.verticalDeadzone)
            }
            return headKeyZone()
        }
    }

    /// Half of the smallest press threshold among the head's keys.
    private func headKeyZone() -> Double {
        let presses = GestureID.allCases
            .filter { $0.isHeadGesture && bindings[$0] != nil }
            .map { thresholds(for: $0).press }
        return (presses.min() ?? Config.Gestures.tiltUp.press) * Config.FloatingCenter.keysZoneFraction
    }

    /// Non-nil when the center must NOT move: something is firing, held or moving.
    private func floatingCenterBusyReason(now: Double) -> String? {
        // Snake waits longer after a turn: the head is often still turned or
        // returning, and following then would make the NEXT turn need extra movement.
        let pause = mode == .snake ? Config.FloatingCenter.snakePauseAfterTurn : Config.FloatingCenter.pauseAfterOutput
        if now - lastHeadOutputAt < pause {
            return mode == .snake ? "a turn just fired" : "a direction just fired"
        }
        if mode == .snake {
            if snake.isHolding { return "a turn is about to fire" }
            if !snake.bothArmed { return "a direction is re-arming" }
            return nil
        }
        // A head key held or about to fire (Keys mode, Minecraft options 2 and 3).
        for gesture in GestureID.allCases where gesture.isHeadGesture {
            guard let binding = bindings[gesture], let detector = gestures[gesture] else { continue }
            switch detector.phase {
            case .active: return "\(binding.label) held"
            case .holding: return "\(binding.label) about to fire"
            case .ready, .waitingForNeutral: continue
            }
        }
        if headAimsNow, aimState.speedX != 0 || aimState.speedY != 0 { return "pointer moving" }
        if mode == .minecraft, headPaused { return "head tilted toward a shoulder" }
        return nil
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

    /// Works out what every gesture does now and builds fresh detectors for it (each
    /// waits for neutral first). The old detectors are thrown away, so the CALLER
    /// must release anything they held first.
    private func refreshBindings() {
        bindings = mode == .minecraft ? minecraft.bindings(job: headSwitch.job) : mode.bindings
        var result: [GestureID: ThresholdGesture] = [:]
        for gesture in GestureID.allCases {
            let limits = thresholds(for: gesture)
            result[gesture] = ThresholdGesture(pressThreshold: limits.press,
                                               releaseThreshold: limits.release,
                                               holdTime: limits.holdTime)
        }
        gestures = result
    }

    /// Press / release / hold time for a gesture in the current mode.
    /// (Snake's head turns use SnakeController's own live settings instead.)
    private func thresholds(for gesture: GestureID) -> GestureThresholds {
        if mode == .minecraft, gesture.isHeadGesture, let walk = minecraft.headWalkThresholds {
            return walk
        }
        return gesture.thresholds
    }

    private func resetAllGestures(requireNeutral: Bool) {
        for gesture in GestureID.allCases {
            gestures[gesture]?.reset(requireNeutral: requireNeutral)
        }
        snake.requireReturn()
        headSwitch.requireNeutral()
    }

    // MARK: - Calibration

    private func beginCalibration() {
        // Block (and release) everything while recording the neutral face.
        input.setBlocked(.calibrating, true)
        aim.stopMoving()
        resetAllGestures(requireNeutral: true)
        calibrator.start()
        // Old values were relative to the old neutral face: don't show them.
        latestValues = [:]
        snapshot.relativeAngles = nil
        snapshot.playerOffset = nil
        snapshot.calibration = .inProgress(progress: 0, faceVisible: snapshot.faceVisible)
        logEvent("Calibration started: look straight at the camera, face relaxed")
        publish(force: true)
    }

    private func finishCalibration(_ result: CalibrationResult) {
        calibration = result
        neutralAngles = result.neutral
        neutralAnchor = result.neutral
        snakeFilter.reset()
        floatingCenter.reset()
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
            if let binding = bindings[gesture], input.isHeld(binding.action) {
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
        if mode == .snake {
            snapshot.snake = makeSnakeStatus(now: now)
        }
        if mode == .minecraft {
            snapshot.minecraft = MinecraftStatus(option: minecraft.option,
                                                 headJob: headSwitch.job,
                                                 headAims: headAimsNow,
                                                 headPaused: headPaused,
                                                 tilt: latestTilt,
                                                 switchTiltDegrees: headSwitch.tiltDegrees,
                                                 switchPhase: headSwitch.phase,
                                                 switchCount: headSwitch.switchCount)
        }
        var floating = FloatingCenterStatus(enabled: floatingSettings.isEnabled(for: mode),
                                            state: floatingCenter.state,
                                            isFollowing: floatingCenter.isFollowing)
        if let neutral = neutralAngles, let anchor = neutralAnchor {
            let shift = PlayerDirections.offset(relative: neutral - anchor, framesMirrored: framesMirrored)
            snapshot.centerShift = shift
            floating.shiftDegrees = hypot(shift.left, shift.up)
        } else {
            snapshot.centerShift = nil
        }
        snapshot.floatingCenter = floating
        snapshot.aim = headAimsNow ? aimState : AimState(sensitivity: aim.currentSensitivity)
        snapshot.gestures = GestureID.allCases.map { gesture in
            let binding = bindings[gesture]
            var firing = false
            if let binding = binding {
                switch binding.style {
                case .hold:
                    firing = input.isHeld(binding.action)
                case .tap:
                    firing = lastTapAt[gesture].map { now - $0 < Config.UI.tapFlashDuration } ?? false
                }
            }
            if mode == .snake && gesture.isHeadGesture {
                return snakeGestureSnapshot(gesture, binding: binding, firing: firing, now: now)
            }
            return GestureSnapshot(gesture: gesture,
                                   value: latestValues[gesture],
                                   thresholds: thresholds(for: gesture),
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

    // MARK: - Snake status for the window

    private func makeSnakeStatus(now: Double) -> SnakeStatus {
        var status = snakeStatus
        status.blocker = snakeBlocker()
        status.horizontalText = snake.horizontal.statusText(settings: snake.settings)
        status.verticalText = snake.vertical.statusText(settings: snake.settings)
        status.horizontalArmed = snake.horizontal.isArmed
        status.verticalArmed = snake.vertical.isArmed
        status.horizontalSpeed = snake.horizontal.speed
        status.verticalSpeed = snake.vertical.speed
        status.secondsSinceLastTurn = lastSnakeTurnAt.map { now - $0 }
        status.averageTurnLatencyMs = snakeLatencies.average
        return status
    }

    /// Why no turn can fire at all right now, in plain language.
    private func snakeBlocker() -> String? {
        if let reason = input.currentBlockReasons.first {
            return "Blocked: \(reason.rawValue)"
        }
        if calibration == nil || calibrator.isCollecting {
            return "Calibrating: look straight at the camera"
        }
        if !snapshot.faceVisible {
            return "No face: look at the camera"
        }
        return nil
    }

    /// Gesture-table row for a Snake direction (uses the live Snake settings).
    private func snakeGestureSnapshot(_ gesture: GestureID, binding: OutputBinding?,
                                      firing: Bool, now: Double) -> GestureSnapshot {
        let isHorizontal = gesture == .turnLeft || gesture == .turnRight
        let axis = isHorizontal ? snake.horizontal : snake.vertical
        let sign: Double = (gesture == .turnLeft || gesture == .tiltUp) ? 1 : -1
        let settings = snake.settings

        let phase: GesturePhase
        switch axis.phase {
        case .armed:
            phase = .ready
        case .holding(let holdSign, let since):
            phase = holdSign == sign
                ? .holding(progress: min(1, (now - since) / max(settings.holdTime, 0.001)))
                : .ready
        case .waitingForReturn:
            phase = .waitingForNeutral
        }
        return GestureSnapshot(gesture: gesture,
                               value: latestValues[gesture],
                               thresholds: GestureThresholds(press: settings.pressDegrees,
                                                             release: settings.rearmDegrees,
                                                             holdTime: settings.holdTime),
                               binding: binding,
                               phase: phase,
                               firing: firing)
    }
}
