import AppKit
import SwiftUI

/// Snake mode's live tuning panel: recenter, why a turn isn't firing, the last
/// turn's latency, and sliders that change the rules instantly (saved between launches).
struct SnakePanel: View {
    @ObservedObject var model: DebugModel
    let controller: AppController

    private var status: SnakeStatus { model.engine.snake }
    private var settings: SnakeSettings { model.snakeSettings }

    var body: some View {
        GroupBox(label: Text("Snake tuning (saved automatically)")) {
            VStack(alignment: .leading, spacing: 8) {
                recenterRow
                Divider()
                whyNotFiring
                Divider()
                lastTurn
                Divider()
                sliders
                Divider()
                yourValues
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Recenter

    private var recenterRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { controller.recenter() }) {
                Text("Recenter now")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .controlSize(.large)
            Text("Look at the screen naturally, then recenter. Hotkey from any app: \(Config.Recenter.description). In this window: R.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !model.recenterHotKeyRegistered {
                Text("⚠️ The recenter hotkey couldn't be registered. Use the button.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Why isn't it firing?

    private var whyNotFiring: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Right now").font(.caption).foregroundColor(.secondary)
            if let blocker = status.blocker {
                Text("⛔︎ \(blocker)")
                    .font(.callout.bold())
                    .foregroundColor(.orange)
            }
            axisLine(armed: status.horizontalArmed, text: status.horizontalText, speed: status.horizontalSpeed)
            axisLine(armed: status.verticalArmed, text: status.verticalText, speed: status.verticalSpeed)
        }
    }

    private func axisLine(armed: Bool, text: String, speed: Double) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(armed ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(format: "head speed %.0f°/s", abs(speed)))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Last turn

    private var lastTurn: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let turn = status.lastTurn {
                let ago = status.secondsSinceLastTurn.map { String(format: "%.1f s ago", $0) } ?? ""
                Text("Last turn: \(turn), \(ago)")
                    .font(.callout)
            } else {
                Text("Last turn: none yet").font(.callout)
            }
            Text("Frame → key: last \(DisplayFormat.milliseconds(status.lastTurnLatencyMs)), average \(DisplayFormat.milliseconds(status.averageTurnLatencyMs))")
                .font(.caption)
                .monospacedDigit()
            Text("Turns: \(status.turnCount) (\(status.flickTurnCount) by flick), \(status.blockedCount) blocked")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Sliders

    /// A binding that edits one field of the Snake settings and sends the result on.
    private func setting(_ keyPath: WritableKeyPath<SnakeSettings, Double>) -> Binding<Double> {
        Binding(
            get: { model.snakeSettings[keyPath: keyPath] },
            set: { newValue in
                var updated = model.snakeSettings
                updated[keyPath: keyPath] = newValue
                controller.setSnakeSettings(updated)
            })
    }

    /// A binding for one of the on/off switches in the Snake settings.
    private func toggle(_ keyPath: WritableKeyPath<SnakeSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.snakeSettings[keyPath: keyPath] },
            set: { newValue in
                var updated = model.snakeSettings
                updated[keyPath: keyPath] = newValue
                controller.setSnakeSettings(updated)
            })
    }

    private var sliders: some View {
        VStack(alignment: .leading, spacing: 6) {
            sliderRow("Press threshold",
                      value: setting(\.pressDegrees), range: Config.Snake.pressRange, step: 0.5,
                      text: String(format: "%.1f°", settings.pressDegrees),
                      help: "How far to turn/tilt for a turn. Lower = less head movement.")
            sliderRow("Re-arm when back below",
                      value: setting(\.rearmFraction), range: Config.Snake.rearmRange, step: 0.05,
                      text: String(format: "%.0f%% (%.1f°)", settings.rearmFraction * 100, settings.rearmDegrees),
                      help: "After a turn, that axis is ready again once you come back below this. Higher = re-arms sooner.")
            sliderRow("Hold time",
                      value: setting(\.holdTime), range: Config.Snake.holdRange, step: 0.01,
                      text: String(format: "%.0f ms", settings.holdTime * 1000),
                      help: "How long to stay past the threshold. 0 = instant (more accidental turns). Flicks skip this.")
            sliderRow("Smoothing",
                      value: setting(\.smoothing), range: Config.Snake.smoothingRange, step: 0.05,
                      text: settings.smoothing < 0.001
                        ? "off"
                        : String(format: "%.0f%% (~%.0f ms lag)", settings.smoothing * 100, settings.smoothingLagMs),
                      help: "Less = faster but jumpier. More = steadier but later.")
            sliderRow("Flick speed",
                      value: setting(\.flickSpeed), range: Config.Snake.flickSpeedRange, step: 5,
                      text: settings.flickSpeed < 1 ? "off" : String(format: "%.0f°/s", settings.flickSpeed),
                      help: "A quick head flick this fast fires right away. Lower = gentler flicks count. 0 = off.")
            sliderRow("Min time between turns",
                      value: setting(\.minTurnInterval), range: Config.Snake.minTurnIntervalRange, step: 0.005,
                      text: String(format: "%.0f ms", settings.minTurnInterval * 1000),
                      help: "Two turns closer than this are spaced out: the second is sent a little later, never dropped.")

            Text("Optional blocks (off = nothing gets eaten; Google Snake ignores reversals and repeats itself)")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: toggle(\.bounceBlockEnabled)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Block bounce-back turns")
                    Text(String(format: "Ignore the opposite direction for %.0f ms after re-arming.",
                                Config.Snake.bounceBlock * 1000))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Toggle(isOn: toggle(\.sameDirectionBlockEnabled)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Block double turns")
                    Text(String(format: "Ignore the same direction twice within %.0f ms.",
                                Config.Snake.sameDirectionCooldown * 1000))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Text("The center following your head (auto-recenter) is now the Floating center setting in the middle column.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    // MARK: - Your values

    private var yourValues: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your values (report these back):")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(settings.summary)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString("Snake: \(settings.summary)", forType: .string)
                }
                Button("Reset to defaults") {
                    controller.resetSnakeSettings()
                }
            }
        }
    }
}
