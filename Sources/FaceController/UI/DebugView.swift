import Foundation
import SwiftUI

/// The debug window: camera preview, direction pad, every gesture's live value,
/// aiming, speed numbers, and controls.
struct DebugView: View {
    @ObservedObject var model: DebugModel
    let controller: AppController

    private var snap: EngineSnapshot { model.engine }

    var body: some View {
        // Scrolls if your screen is smaller than the window's content.
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 12) {
                permissionBanners
                HStack(alignment: .top, spacing: 16) {
                    // Column 1: what the camera sees.
                    VStack(alignment: .leading, spacing: 10) {
                        preview
                        cameraInfo
                        GroupBox(label: Text("Direction (your point of view)")) {
                            DirectionPad(offset: snap.playerOffset, centerShift: snap.centerShift,
                                         boxHalfWidth: padBox.width, boxHalfHeight: padBox.height)
                                .frame(maxWidth: .infinity)
                        }
                        performanceBox
                    }
                    .frame(width: 400)

                    // Column 2: control, mode, calibration, gestures.
                    VStack(alignment: .leading, spacing: 10) {
                        controlBox
                        modeBox
                        calibrationBox
                        FloatingCenterBox(model: model, controller: controller)
                        GroupBox(label: Text("Gestures")) {
                            GestureTable(gestures: snap.gestures,
                                         mode: snap.mode,
                                         isSnake: showsTurnLog)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if showsTurnLog {
                            TurnLogView(entries: snap.snake.turnLog)
                        }
                    }
                    .frame(width: 500)

                    // Column 3: aiming, raw numbers, events.
                    VStack(alignment: .leading, spacing: 10) {
                        if snap.mode == .snake {
                            SnakePanel(model: model, controller: controller)
                        } else if snap.mode == .minecraft {
                            MinecraftPanel(model: model, controller: controller)
                            aimBox
                        } else if snap.mode == .scroll {
                            ScrollPanel(model: model, controller: controller)
                            if model.scrollSettings.option == .shorts {
                                SnakePanel(model: model, controller: controller, forShorts: true)
                            }
                        } else {
                            aimBox
                        }
                        headBox
                        eventLog
                    }
                    .frame(width: 360)
                }
            }
            .padding(16)
        }
    }

    /// Snake, and Scroll mode's Shorts: the same tap logic, so the same Turn log.
    private var showsTurnLog: Bool {
        snap.mode == .snake || (snap.mode == .scroll && model.scrollSettings.option == .shorts)
    }

    /// The Direction pad's dashed box (degrees): where things fire in this mode, or
    /// the aim deadzone when the head aims.
    private var padBox: (width: Double, height: Double) {
        let deadzone = (width: Config.Aim.horizontalDeadzone, height: Config.Aim.verticalDeadzone)
        switch snap.mode {
        case .keys:
            return (width: Config.Gestures.turnLeft.press, height: Config.Gestures.tiltUp.press)
        case .aim:
            return deadzone
        case .snake:
            return (width: model.snakeSettings.pressDegrees, height: model.snakeSettings.pressDegrees)
        case .minecraft:
            let settings = model.minecraftSettings
            switch settings.option {
            case .faceMoves:
                return deadzone
            case .modeSwitch:
                if snap.minecraft.headJob == .move {
                    return (width: settings.moveDegrees, height: settings.moveDegrees)
                }
                return deadzone
            case .splitZones:
                // The walk zone: inside it the head only aims.
                return (width: settings.walkZoneDegrees, height: settings.walkZoneDegrees)
            }
        case .scroll:
            switch model.scrollSettings.option {
            case .smooth:
                let deadzone = model.scrollSettings.deadzoneDegrees
                return (width: deadzone, height: deadzone)
            case .shorts:
                let press = model.shortsSettings.pressDegrees
                return (width: press, height: press)
            }
        }
    }

    // MARK: - Permission instructions

    @ViewBuilder
    private var permissionBanners: some View {
        let app = Permissions.responsibleAppName

        switch model.cameraPermission {
        case .denied, .restricted:
            Banner(title: "Camera access is off",
                   lines: [
                       "1. Open System Settings → Privacy & Security → Camera.",
                       "2. Turn ON \"\(app)\" (when you start the app from \(app), macOS gives the permission to \(app)).",
                       "3. Quit Face Controller (and \(app) if macOS asks), then run it again."
                   ],
                   buttonTitle: "Open Camera Settings",
                   action: { Permissions.openCameraSettings() })
        case .notDetermined:
            Banner(title: "Waiting for camera permission",
                   lines: ["Click OK in the system dialog that asks whether \"\(app)\" may use the camera."],
                   color: .blue)
        case .authorized:
            EmptyView()
        }

        if !model.accessibilityGranted {
            Banner(title: "Accessibility access is off, so keys and mouse can't be sent",
                   lines: [
                       "1. Open System Settings → Privacy & Security → Accessibility.",
                       "2. Turn ON \"\(app)\". Not listed? Click +, then add it (Terminal is in Applications → Utilities).",
                       "3. This window notices within a second. If input still doesn't arrive, quit and run again."
                   ],
                   buttonTitle: "Open Accessibility Settings",
                   action: { Permissions.openAccessibilitySettings() })
        }

        if let error = model.cameraError {
            Banner(title: "Camera problem",
                   lines: [error],
                   buttonTitle: "Retry camera",
                   action: { controller.retryCamera() })
        }
    }

    // MARK: - Camera preview

    /// (progress, faceVisible) while calibrating, nil otherwise.
    private var calibrationProgress: (progress: Double, faceVisible: Bool)? {
        if case .inProgress(let progress, let faceVisible) = snap.calibration {
            return (progress, faceVisible)
        }
        return nil
    }

    private var preview: some View {
        ZStack {
            CameraPreview(session: controller.camera.session)

            if let calibrating = calibrationProgress {
                VStack(spacing: 8) {
                    Text(calibrating.faceVisible ? "Look straight at the camera" : "Face not found: look at the camera")
                        .font(.title2.bold())
                    Text("Mouth closed, eyebrows relaxed")
                        .font(.callout)
                    ProgressView(value: calibrating.progress)
                        .frame(width: 240)
                    Text("Hold still… \(Int(calibrating.progress * 100))%")
                        .font(.callout)
                }
                .padding(16)
                .foregroundColor(.white)
                .background(Color.black.opacity(0.65))
                .cornerRadius(10)
            } else if model.cameraStarting {
                Text("Starting camera…")
                    .foregroundColor(.white)
            }
        }
        .frame(width: 400, height: 300)
        .background(Color.black)
        .cornerRadius(8)
    }

    private var cameraInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let info = model.cameraInfo {
                Text("Camera: \(info.deviceName), \(info.width)×\(info.height) @ \(String(format: "%.0f", info.frameRate)) fps")
                    .font(.caption)
                if let note = info.note {
                    Text(note).font(.caption).foregroundColor(.secondary)
                }
                Text(info.framesMirrored
                     ? "Preview mirrored like a selfie. Camera frames arrive mirrored (corrected automatically)."
                     : "Preview mirrored like a selfie. Camera frames arrive unmirrored (corrected automatically).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Camera: not running").font(.caption).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Control

    private var controlBox: some View {
        GroupBox(label: Text("Control")) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(model.controlEnabled ? "ON" : "OFF")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(model.controlEnabled ? .green : .red)
                    Spacer()
                    Button(model.controlEnabled ? "Turn OFF" : "Turn ON") {
                        controller.toggleControl()
                    }
                }
                Text("Kill switch from any app: \(Config.Safety.killSwitchDescription)")
                    .font(.caption)
                if !model.killSwitchRegistered {
                    Text("⚠️ The kill-switch hotkey couldn't be registered. Use the button instead.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                if !snap.blockReasons.isEmpty {
                    Text("Input blocked: " + snap.blockReasons.map { $0.rawValue }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                if !heldOutputs.isEmpty {
                    Text("Held right now: " + heldOutputs.joined(separator: ", "))
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Labels of everything currently held (e.g. "Space", "left mouse").
    private var heldOutputs: [String] {
        snap.gestures.compactMap { row in
            guard row.firing, let binding = row.binding, binding.style == .hold else { return nil }
            return binding.label
        }
    }

    // MARK: - Mode

    private var modeSelection: Binding<ControlMode> {
        Binding(get: { model.mode }, set: { controller.setMode($0) })
    }

    private var modeDescription: String {
        switch model.mode {
        case .keys:
            return "Head presses movement keys, face does actions."
        case .aim:
            return "Head moves the mouse like a joystick. Space/A/D are off (the Minecraft preset tries ways for the head to do both)."
        case .snake:
            return "For Google Snake: each turn or quick flick of your head taps one arrow key. After a turn, that direction re-arms as soon as you come partway back. Tune it live in the Snake panel (right). Expressions are off."
        case .minecraft:
            return "For Minecraft Classic (classic.minecraft.net): the head walks AND looks around, in one of three ways. Pick the head option in the Minecraft panel (right)."
        case .scroll:
            return "For YouTube and other pages: tilt to scroll smoothly, or flick to the next / previous Short. Pick the option in the Scroll panel (right)."
        }
    }

    private var modeBox: some View {
        GroupBox(label: Text("Mode")) {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Mode", selection: modeSelection) {
                    ForEach(ControlMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(modeDescription)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Switching mode releases everything.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Calibration

    private var calibrationText: String {
        switch snap.calibration {
        case .notStarted:
            return "Not calibrated yet"
        case .inProgress(let progress, let faceVisible):
            let hint = faceVisible ? "look straight at the camera" : "face not found"
            return "Calibrating… \(Int(progress * 100))% (\(hint))"
        case .done(let result):
            var text = String(format: "Calibrated ✓  neutral pitch %+.1f°, yaw %+.1f°", result.neutral.pitch, result.neutral.yaw)
            if let expressions = result.neutralExpressions {
                text += String(format: ", mouth %.0f%%, brows %.0f%%", expressions.mouthOpen, expressions.browHeight)
            } else {
                text += "\nCouldn't read mouth/eyebrows: expressions are off until you recalibrate."
            }
            return text
        }
    }

    /// Jitter (how much each value wobbled while you held still), and a warning
    /// when it's large compared with that gesture's press threshold.
    private var jitterText: String? {
        guard case .done(let result) = snap.calibration else { return nil }
        var text = String(format: "Jitter: pitch ±%.1f°, yaw ±%.1f°", result.pitchJitter, result.yawJitter)
        if let mouth = result.mouthJitter, let brow = result.browJitter {
            text += String(format: ", mouth ±%.1f%%, brows ±%.1f%%", mouth, brow)
        }
        return text
    }

    private var noisyWarnings: [String] {
        guard case .done(let result) = snap.calibration else { return [] }
        // "Noisy" = the wobble while still is over a third of the press threshold.
        var warnings: [String] = []
        if result.pitchJitter > Config.Gestures.tiltUp.press / 3 {
            warnings.append("Head up/down reading is noisy (did you move?).")
        }
        if result.yawJitter > Config.Gestures.turnLeft.press / 3 {
            warnings.append("Head left/right reading is noisy (did you move?).")
        }
        if let mouth = result.mouthJitter, mouth > Config.Gestures.mouthOpen.press / 3 {
            warnings.append("Mouth reading is noisy compared with its threshold.")
        }
        if let brow = result.browJitter, brow > Config.Gestures.eyebrowsRaise.press / 3 {
            warnings.append("Eyebrow reading is noisy compared with its threshold: expect false triggers.")
        }
        return warnings
    }

    private var calibrationBox: some View {
        GroupBox(label: Text("Calibration")) {
            VStack(alignment: .leading, spacing: 6) {
                Text(calibrationText)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let jitter = jitterText {
                    Text(jitter)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ForEach(noisyWarnings, id: \.self) { warning in
                    Text("⚠️ \(warning) Press C to redo.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                HStack {
                    // keyboardShortcut: the key presses this button while this window is focused.
                    Button("Recenter now (R)") {
                        controller.recenter()
                    }
                    .keyboardShortcut("r", modifiers: [])
                    .controlSize(.large)
                    Button("Recalibrate (C)") {
                        controller.recalibrate()
                    }
                    .keyboardShortcut("c", modifiers: [])
                }
                Text("Recenter = \"where my head is now is neutral\", instantly (also \(Config.Recenter.description) from any app). Recalibrate = 3 s, also re-measures mouth and eyebrows.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Aiming

    private var sensitivitySelection: Binding<Double> {
        Binding(get: { model.aimSensitivity }, set: { controller.setAimSensitivity($0) })
    }

    private func speedText(_ speed: Double, inDeadzone: Bool, positive: String, negative: String) -> String {
        if inDeadzone || speed == 0 { return "still (deadzone)" }
        let arrow = speed > 0 ? positive : negative
        return "\(arrow) \(String(format: "%.0f", abs(speed))) pt/s"
    }

    private var aimBox: some View {
        GroupBox(label: Text("Head-to-mouse aiming")) {
            VStack(alignment: .leading, spacing: 6) {
                if !snap.mode.usesAim {
                    Text("Off. Pick “Aim (mouse)” or “Minecraft” in Mode to use aiming.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if !snap.aim.active {
                    Text("Not aiming right now (calibrating, no face, Minecraft option 2 in MOVE, or head tilted to switch).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text("Sensitivity")
                    Slider(value: sensitivitySelection, in: Config.Aim.sensitivityRange)
                    Text(String(format: "%.2f×", model.aimSensitivity))
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    GridRow {
                        Text("")
                        Text("Head").foregroundColor(.secondary)
                        Text("Pointer").foregroundColor(.secondary)
                    }
                    GridRow {
                        Text("Left / right")
                        Text(DisplayFormat.degrees(snap.playerOffset?.left)).monospacedDigit()
                        Text(snap.aim.active
                             ? speedText(snap.aim.speedX, inDeadzone: snap.aim.inDeadzoneX, positive: "→", negative: "←")
                             : "—")
                            .monospacedDigit()
                    }
                    GridRow {
                        Text("Up / down")
                        Text(DisplayFormat.degrees(snap.playerOffset?.up)).monospacedDigit()
                        Text(snap.aim.active
                             ? speedText(snap.aim.speedY, inDeadzone: snap.aim.inDeadzoneY, positive: "↑", negative: "↓")
                             : "—")
                            .monospacedDigit()
                    }
                }
                .font(.callout)
                Text(String(format: "Deadzone ±%.1f° / ±%.1f°, full speed at %.0f° / %.0f°, max %.0f / %.0f pt/s, curve ^%.1f",
                            Config.Aim.horizontalDeadzone, Config.Aim.verticalDeadzone,
                            Config.Aim.horizontalFullSpeedAngle, Config.Aim.verticalFullSpeedAngle,
                            Config.Aim.maxSpeedX, Config.Aim.maxSpeedY, Config.Aim.curveExponent))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Head and face numbers

    private var faceText: String {
        if snap.anglesMissing { return "Face found, but Vision gave no head angles" }
        if snap.faceVisible { return String(format: "Detected (confidence %.2f)", snap.faceConfidence) }
        return "NOT FOUND"
    }

    private var neutralExpressions: ExpressionValues? {
        if case .done(let result) = snap.calibration {
            return result.neutralExpressions
        }
        return nil
    }

    private var headBox: some View {
        GroupBox(label: Text("Head and face")) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Face:")
                    Text(faceText)
                        .foregroundColor(snap.faceVisible ? .primary : .red)
                }
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                    GridRow {
                        Text("")
                        Text("Raw (Vision)").foregroundColor(.secondary)
                        Text("vs. neutral").foregroundColor(.secondary)
                    }
                    GridRow {
                        Text("Pitch (nod)")
                        Text(DisplayFormat.degrees(snap.rawAngles?.pitch)).monospacedDigit()
                        Text(DisplayFormat.degrees(snap.relativeAngles?.pitch)).monospacedDigit()
                    }
                    GridRow {
                        Text("Yaw (turn)")
                        Text(DisplayFormat.degrees(snap.rawAngles?.yaw)).monospacedDigit()
                        Text(DisplayFormat.degrees(snap.relativeAngles?.yaw)).monospacedDigit()
                    }
                    GridRow {
                        Text("Roll (tilt)")
                        Text(DisplayFormat.degrees(snap.rawAngles?.roll)).monospacedDigit()
                        Text(DisplayFormat.degrees(snap.relativeAngles?.roll)).monospacedDigit()
                    }
                    GridRow {
                        Text("Mouth open")
                        Text(DisplayFormat.percent(snap.expressions?.mouthOpen)).monospacedDigit()
                        Text("neutral \(DisplayFormat.percent(neutralExpressions?.mouthOpen))")
                            .foregroundColor(.secondary)
                    }
                    GridRow {
                        Text("Eyebrows")
                        Text(DisplayFormat.percent(snap.expressions?.browHeight)).monospacedDigit()
                        Text("neutral \(DisplayFormat.percent(neutralExpressions?.browHeight))")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.callout)
                Text("Mouth and eyebrows are in % of the distance between your eyes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Events

    private var eventLog: some View {
        GroupBox(label: Text("Recent events")) {
            VStack(alignment: .leading, spacing: 2) {
                if snap.recentEvents.isEmpty {
                    Text("Nothing yet").foregroundColor(.secondary)
                }
                ForEach(snap.recentEvents.indices, id: \.self) { index in
                    Text(snap.recentEvents[index])
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(.caption, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Performance

    private var performanceBox: some View {
        GroupBox(label: Text("Speed")) {
            VStack(alignment: .leading, spacing: 6) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                    GridRow {
                        Text("Camera FPS")
                        Text(String(format: "%.1f", snap.cameraFPS)).monospacedDigit()
                    }
                    GridRow {
                        Text("Dropped (late) frames")
                        Text("\(snap.droppedFrames)").monospacedDigit()
                    }
                    GridRow {
                        Text("Vision time / frame")
                        Text("\(DisplayFormat.milliseconds(snap.visionMs))  (landmarks \(DisplayFormat.milliseconds(snap.landmarksMs)))")
                            .monospacedDigit()
                    }
                    GridRow {
                        Text("Total processing / frame")
                        Text("\(DisplayFormat.milliseconds(snap.processingMs))  (max \(DisplayFormat.milliseconds(snap.processingMaxMs)))")
                            .monospacedDigit()
                    }
                    GridRow {
                        Text("Camera delay (capture → app)")
                        Text(DisplayFormat.milliseconds(snap.cameraDelayMs)).monospacedDigit()
                    }
                    GridRow {
                        Text("Frame → key/click (last)")
                        Text(DisplayFormat.milliseconds(snap.lastOutputLatencyMs)).monospacedDigit()
                    }
                    GridRow {
                        Text("Frame → key/click (avg)")
                        Text("\(DisplayFormat.milliseconds(snap.averageOutputLatencyMs))  (\(snap.outputEventCount) events)")
                            .monospacedDigit()
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Frame → key/click = camera capture to event sent. Each gesture's hold time is on top of this, on purpose.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let seconds = snap.secondsSinceLastFrame, seconds > 0.5 {
                    Text(String(format: "⚠️ No camera frames for %.1f s", seconds))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                if let error = snap.visionError {
                    Text("Vision error: \(error)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }
}
