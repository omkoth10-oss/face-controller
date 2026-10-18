import Foundation
import SwiftUI

/// The Phase 1 debug window: camera preview, live numbers, and controls.
struct DebugView: View {
    @ObservedObject var model: DebugModel
    let controller: AppController

    private var snap: EngineSnapshot { model.engine }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            permissionBanners
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    preview
                    cameraInfo
                    performanceBox
                }
                .frame(width: 440)

                VStack(alignment: .leading, spacing: 10) {
                    controlBox
                    calibrationBox
                    gestureBox
                    headBox
                    eventLog
                }
                .frame(width: 380)
            }
        }
        .padding(16)
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
            Banner(title: "Accessibility access is off, so key presses can't be sent",
                   lines: [
                       "1. Open System Settings → Privacy & Security → Accessibility.",
                       "2. Turn ON \"\(app)\". Not listed? Click +, then add it (Terminal is in Applications → Utilities).",
                       "3. This window notices within a second. If keys still don't arrive, quit and run again."
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
                    ProgressView(value: calibrating.progress)
                        .frame(width: 240)
                    Text("Relax and hold still… \(Int(calibrating.progress * 100))%")
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
        .frame(width: 440, height: 330)
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
            } else {
                Text("Camera: not running").font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var eventLog: some View {
        GroupBox(label: Text("Recent events")) {
            VStack(alignment: .leading, spacing: 2) {
                if snap.recentEvents.isEmpty {
                    Text("Nothing yet").foregroundColor(.secondary)
                }
                ForEach(snap.recentEvents.indices, id: \.self) { index in
                    Text(snap.recentEvents[index])
                }
            }
            .font(.system(.caption, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text("Keys blocked: " + snap.blockReasons.map { $0.rawValue }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
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
            return String(format: "Calibrated ✓  neutral pitch %+.1f°, yaw %+.1f°, roll %+.1f°  (jitter ±%.1f°)",
                          result.neutral.pitch, result.neutral.yaw, result.neutral.roll, result.pitchJitter)
        }
    }

    /// True if your head moved noticeably during the last calibration.
    private var calibrationWasShaky: Bool {
        if case .done(let result) = snap.calibration {
            return result.pitchJitter > 2
        }
        return false
    }

    private var calibrationBox: some View {
        GroupBox(label: Text("Calibration")) {
            VStack(alignment: .leading, spacing: 6) {
                Text(calibrationText)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if calibrationWasShaky {
                    Text("Your head moved while calibrating. Press C to redo it.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                // keyboardShortcut makes the C key press this button while this window is focused.
                Button("Recalibrate (C)") {
                    controller.recalibrate()
                }
                .keyboardShortcut("c", modifiers: [])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Gesture

    private var phaseText: String {
        switch snap.gesturePhase {
        case .waitingForNeutral: return "Return to neutral to arm"
        case .ready: return "Ready"
        case .holding(let progress): return "Hold… \(Int(progress * 100))%"
        case .active: return "Firing"
        }
    }

    private var keyStatusText: String {
        let name = Config.TiltUp.keyName
        return snap.keyHeld ? "\(name.uppercased()) HELD" : "\(name) released"
    }

    private var closenessText: String {
        guard let value = snap.tiltUpDegrees else { return "—" }
        let percent = Int((max(0, value) / Config.TiltUp.pressDegrees * 100).rounded())
        return "\(percent)% of the way to pressing"
    }

    private var gestureBox: some View {
        GroupBox(label: Text("Tilt head UP → hold \(Config.TiltUp.keyName)")) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Tilt up:")
                    Text(DisplayFormat.degrees(snap.tiltUpDegrees))
                        .font(.title3)
                        .monospacedDigit()
                    Spacer()
                    Text(closenessText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ThresholdBar(value: snap.tiltUpDegrees,
                             pressThreshold: Config.TiltUp.pressDegrees,
                             releaseThreshold: Config.TiltUp.releaseDegrees,
                             isHeld: snap.keyHeld)
                Text(String(format: "Red line: press at %.1f°   Orange line: release below %.1f°   Hold: %.0f ms",
                            Config.TiltUp.pressDegrees,
                            Config.TiltUp.releaseDegrees,
                            Config.TiltUp.holdTime * 1000))
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Text(keyStatusText)
                        .font(.headline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(snap.keyHeld ? Color.green : Color.gray.opacity(0.25))
                        .foregroundColor(snap.keyHeld ? .black : .primary)
                        .cornerRadius(6)
                    Spacer()
                    Text(phaseText)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Head angles

    private var faceText: String {
        if snap.anglesMissing { return "Face found, but Vision gave no head angles" }
        if snap.faceVisible { return String(format: "Detected (confidence %.2f)", snap.faceConfidence) }
        return "NOT FOUND"
    }

    private var headBox: some View {
        GroupBox(label: Text("Head")) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Face:")
                    Text(faceText)
                        .foregroundColor(snap.faceVisible ? .primary : .red)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
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
                }
                .font(.callout)
            }
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
                        Text(DisplayFormat.milliseconds(snap.visionMs)).monospacedDigit()
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
                        Text("Frame → key event (last)")
                        Text(DisplayFormat.milliseconds(snap.lastKeyLatencyMs)).monospacedDigit()
                    }
                    GridRow {
                        Text("Frame → key event (avg)")
                        Text("\(DisplayFormat.milliseconds(snap.averageKeyLatencyMs))  (\(snap.keyEventCount) events)")
                            .monospacedDigit()
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Frame → key = camera capture to key event sent. The \(Int(Config.TiltUp.holdTime * 1000)) ms hold time is on top of this, on purpose.")
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

// MARK: - Small building blocks

/// Number formatting used in the window. "—" means "no value yet".
enum DisplayFormat {
    static func degrees(_ value: Double?) -> String {
        guard let value = value else { return "—" }
        return String(format: "%+.1f°", value)
    }

    static func milliseconds(_ value: Double?) -> String {
        guard let value = value else { return "—" }
        return String(format: "%.1f ms", value)
    }
}

/// A colored box with instructions and an optional button.
struct Banner: View {
    let title: String
    let lines: [String]
    var buttonTitle: String?
    var action: (() -> Void)?
    var color: Color = .red

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let buttonTitle = buttonTitle, let action = action {
                Button(buttonTitle, action: action)
                    .padding(.top, 4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.15))
        .cornerRadius(8)
    }
}

/// Horizontal bar showing how far the head is tilted, with the release (orange)
/// and press (red) thresholds marked.
struct ThresholdBar: View {
    let value: Double?
    let pressThreshold: Double
    let releaseThreshold: Double
    let isHeld: Bool

    /// The bar's right edge is 1.5× the press threshold, so you can see overshoot.
    private var scaleMax: Double { max(pressThreshold * 1.5, 1) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                RoundedRectangle(cornerRadius: 4)
                    .fill(fillColor)
                    .frame(width: geometry.size.width * fraction(value ?? 0))
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 2)
                    .offset(x: geometry.size.width * fraction(releaseThreshold) - 1)
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
                    .offset(x: geometry.size.width * fraction(pressThreshold) - 1)
            }
        }
        .frame(height: 20)
    }

    private func fraction(_ x: Double) -> CGFloat {
        CGFloat(min(1, max(0, x / scaleMax)))
    }

    private var fillColor: Color {
        if isHeld { return .green }
        guard let value = value else { return .gray }
        if value >= pressThreshold { return .yellow }
        if value >= releaseThreshold { return .orange.opacity(0.7) }
        return .blue
    }
}
