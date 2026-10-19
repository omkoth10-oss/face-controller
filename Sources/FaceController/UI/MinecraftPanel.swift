import SwiftUI

/// Minecraft preset panel: pick how the head shares moving and aiming (Phase 3),
/// see what every gesture does, and tune the option's numbers (saved automatically).
struct MinecraftPanel: View {
    @ObservedObject var model: DebugModel
    let controller: AppController

    private var settings: MinecraftSettings { model.minecraftSettings }
    private var status: MinecraftStatus { model.engine.minecraft }

    var body: some View {
        GroupBox(label: Text("Minecraft (classic.minecraft.net)")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How the head moves AND aims:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Head option", selection: optionBinding) {
                    ForEach(HeadOption.allCases) { option in
                        Text(option.shortTitle).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(explanation)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                cheatSheet

                Divider()
                switch settings.option {
                case .faceMoves:
                    Text("Tune the look speed with Sensitivity in the aiming box below.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .modeSwitch:
                    modeSwitchControls
                case .splitZones:
                    splitZoneControls
                }

                Divider()
                Toggle("Show the MOVE / AIM label over the game", isOn: overlayBinding)
                Text("A small label at the top of the screen. It never takes the mouse or keyboard from the game.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Reset Minecraft settings to defaults") {
                    controller.resetMinecraftSettings()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - What the option does

    private var explanation: String {
        switch settings.option {
        case .faceMoves:
            return "Your head only looks around, like the mouse. Your face walks: open your mouth to walk forward, raise your eyebrows to jump. (Nothing is left for clicking in this option.)"
        case .modeSwitch:
            return "Tilt your head toward either shoulder (like a curious dog) to switch it between MOVE and AIM. In MOVE, turning and tilting walk. In AIM, your head looks around. You'll hear a sound on every switch."
        case .splitZones:
            return String(format: "Small head moves look around. Go further than %.0f° and you ALSO walk that way, while still turning.",
                          settings.walkZoneDegrees)
        }
    }

    /// One input and what it does in this option.
    private struct CheatLine: Hashable {
        let input: String
        let action: String
    }

    private var cheatSheetLines: [CheatLine] {
        switch settings.option {
        case .faceMoves:
            return [CheatLine(input: "Head", action: "look around (mouse)"),
                    CheatLine(input: "Open mouth", action: "walk forward (hold W)"),
                    CheatLine(input: "Raise eyebrows", action: "jump (hold Space)")]
        case .modeSwitch:
            return [CheatLine(input: "Tilt to a shoulder", action: "switch MOVE ↔ AIM"),
                    CheatLine(input: "Head in MOVE", action: "up W · down S · left A · right D"),
                    CheatLine(input: "Head in AIM", action: "look around (mouse)"),
                    CheatLine(input: "Open mouth", action: "break block (hold left click)"),
                    CheatLine(input: "Raise eyebrows", action: "jump (hold Space)")]
        case .splitZones:
            return [CheatLine(input: "Head, small", action: "look around (mouse)"),
                    CheatLine(input: "Head, far", action: "look + walk: up W · down S · left A · right D"),
                    CheatLine(input: "Open mouth", action: "break block (hold left click)"),
                    CheatLine(input: "Raise eyebrows", action: "jump (hold Space)")]
        }
    }

    private var cheatSheet: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
            ForEach(cheatSheetLines, id: \.input) { line in
                GridRow {
                    Text(line.input).foregroundColor(.secondary)
                    Text(line.action)
                }
            }
        }
        .font(.caption)
    }

    // MARK: - Option 2: Mode switch

    private var modeSwitchControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text(status.headJob.title)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(status.headJob == .move ? .green : .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.headJob == .move ? "Head walks (W A S D)" : "Head looks around (mouse)")
                        .font(.callout)
                    if status.headPaused {
                        Text("Head tilted: walking/aiming paused (stuck like this? press Recenter)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                Spacer()
                Button("Switch now") {
                    controller.toggleHeadJob()
                }
            }
            HStack(spacing: 8) {
                Text("Shoulder tilt")
                    .font(.caption)
                ThresholdBar(value: status.tilt,
                             pressThreshold: status.switchTiltDegrees,
                             releaseThreshold: status.switchTiltDegrees * Config.Minecraft.switchReleaseFraction,
                             isFiring: status.switchPhase == .active)
                    .frame(width: 110, height: 8)
                Text("\(DisplayFormat.degrees(status.tilt)) (switches at \(Int(status.switchTiltDegrees))°)")
                    .font(.caption)
                    .monospacedDigit()
            }
            Text(switchStateText)
                .font(.caption)
                .foregroundColor(.secondary)
            sliderRow("Switch tilt",
                      value: setting(\.switchTiltDegrees), range: Config.Minecraft.switchTiltRange, step: 1,
                      text: String(format: "%.0f°", settings.switchTiltDegrees),
                      help: "How far to tilt toward a shoulder to switch. Higher = harder to switch by accident.")
            sliderRow("Walk threshold (MOVE)",
                      value: setting(\.moveDegrees), range: Config.Minecraft.moveRange, step: 0.5,
                      text: String(format: "%.1f°", settings.moveDegrees),
                      help: "In MOVE: how far to turn/tilt to walk. Lower = less head movement.")
        }
    }

    private var switchStateText: String {
        let switches = "Switched \(status.switchCount) times."
        switch status.switchPhase {
        case .waitingForNeutral:
            return "Bring your head back upright to arm the switch. \(switches)"
        case .ready:
            return "Ready to switch. \(switches)"
        case .holding(let progress):
            return "Switching… \(Int(progress * 100))%"
        case .active:
            return "Switched! Bring your head back upright. \(switches)"
        }
    }

    // MARK: - Option 3: Split zones

    private var splitZoneControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(walkingText)
                .font(.callout.bold())
                .foregroundColor(walkingLabels.isEmpty ? .secondary : .green)
            sliderRow("Walk zone starts at",
                      value: setting(\.walkZoneDegrees), range: Config.Minecraft.walkZoneRange, step: 0.5,
                      text: String(format: "%.1f°", settings.walkZoneDegrees),
                      help: String(format: "Inside this the head only looks around (it starts moving the view past %.1f°). Past it, the head also walks. Higher = less accidental walking.",
                                   Config.Aim.horizontalDeadzone))
        }
    }

    /// Head walk keys held right now (e.g. ["W"]).
    private var walkingLabels: [String] {
        model.engine.gestures.compactMap { row in
            guard row.gesture.isHeadGesture, row.firing, let binding = row.binding else { return nil }
            return binding.label
        }
    }

    private var walkingText: String {
        walkingLabels.isEmpty ? "Aiming only (inside the walk zone)" : "Walking: \(walkingLabels.joined(separator: " + "))"
    }

    // MARK: - Bindings and helpers

    private var optionBinding: Binding<HeadOption> {
        Binding(
            get: { model.minecraftSettings.option },
            set: { newValue in
                var updated = model.minecraftSettings
                updated.option = newValue
                controller.setMinecraftSettings(updated)
            })
    }

    private var overlayBinding: Binding<Bool> {
        Binding(
            get: { model.minecraftSettings.overlayEnabled },
            set: { newValue in
                var updated = model.minecraftSettings
                updated.overlayEnabled = newValue
                controller.setMinecraftSettings(updated)
            })
    }

    /// A binding that edits one number of the Minecraft settings and sends it on.
    private func setting(_ keyPath: WritableKeyPath<MinecraftSettings, Double>) -> Binding<Double> {
        Binding(
            get: { model.minecraftSettings[keyPath: keyPath] },
            set: { newValue in
                var updated = model.minecraftSettings
                updated[keyPath: keyPath] = newValue
                controller.setMinecraftSettings(updated)
            })
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           step: Double, text: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(title)
                Spacer()
                Text(text)
                    .monospacedDigit()
                    .foregroundColor(.accentColor)
            }
            Slider(value: value, in: range, step: step)
            Text(help)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
