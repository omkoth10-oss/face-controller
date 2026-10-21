import SwiftUI

/// Scroll mode panel: pick smooth scrolling or Shorts, tune it, and switch the
/// mouth's play/pause on or off (all saved automatically). Shorts' flick sliders
/// are the Snake-style panel shown below this one.
struct ScrollPanel: View {
    @ObservedObject var model: DebugModel
    let controller: AppController

    private var settings: ScrollSettings { model.scrollSettings }
    private var state: ScrollState { model.engine.scroll }

    var body: some View {
        GroupBox(label: Text("Scroll (YouTube and other pages)")) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Scroll option", selection: optionBinding) {
                    ForEach(ScrollOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(explanation)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                switch settings.option {
                case .smooth:
                    smoothControls
                case .shorts:
                    Text("Tune the flicks in the Shorts panel below. Every flick and every blocked flick shows in the Turn log (middle column).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                Toggle("Open mouth = play / pause (Space)", isOn: toggle(\.mouthPlayPauseEnabled))
                Text(String(format: "Keep your mouth open about %.1f s. Talking and quick laughs won't pause.",
                            Config.Scroll.mouthHoldTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Reset Scroll settings to defaults") {
                    controller.resetScrollSettings()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var explanation: String {
        switch settings.option {
        case .smooth:
            return "Tilt your head down to scroll down, up to scroll up. The further you tilt, the faster it goes; look back to center and it stops. It scrolls whatever is under the mouse pointer."
        case .shorts:
            return "One quick nod down = next Short (↓). One quick nod up = previous Short (↑). Come back to center before the next one."
        }
    }

    // MARK: - Smooth scrolling

    private var speedText: String {
        guard state.active else { return "—" }
        if state.speed == 0 { return "still (inside the deadzone)" }
        let direction = state.speed > 0 ? "↓ down" : "↑ up"
        return "\(direction) \(Int(abs(state.speed))) points/s"
    }

    private var smoothControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Scrolling:")
                Text(speedText)
                    .font(.callout.bold())
                    .monospacedDigit()
                    .foregroundColor(state.speed == 0 ? .secondary : .green)
            }
            sliderRow("Deadzone",
                      value: setting(\.deadzoneDegrees), range: Config.Scroll.deadzoneRange, step: 0.5,
                      text: String(format: "±%.1f°", settings.deadzoneDegrees),
                      help: "No scrolling while your head is within this much of center. Raise it if small nods scroll.")
            sliderRow("Speed",
                      value: setting(\.speed), range: Config.Scroll.speedRange, step: 0.05,
                      text: String(format: "%.2f×", settings.speed),
                      help: String(format: "Full speed (%.0f points/s at 1×) at %.0f° of tilt. It speeds up smoothly and slows down quickly.",
                                   Config.Scroll.maxSpeed, Config.Scroll.fullSpeedDegrees))
            Toggle("Reverse direction", isOn: toggle(\.reverse))
            Text("Only if tilting down scrolls UP on your Mac.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Bindings and helpers

    private var optionBinding: Binding<ScrollOption> {
        Binding(
            get: { model.scrollSettings.option },
            set: { newValue in
                var updated = model.scrollSettings
                updated.option = newValue
                controller.setScrollSettings(updated)
            })
    }

    private func setting(_ keyPath: WritableKeyPath<ScrollSettings, Double>) -> Binding<Double> {
        Binding(
            get: { model.scrollSettings[keyPath: keyPath] },
            set: { newValue in
                var updated = model.scrollSettings
                updated[keyPath: keyPath] = newValue
                controller.setScrollSettings(updated)
            })
    }

    private func toggle(_ keyPath: WritableKeyPath<ScrollSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.scrollSettings[keyPath: keyPath] },
            set: { newValue in
                var updated = model.scrollSettings
                updated[keyPath: keyPath] = newValue
                controller.setScrollSettings(updated)
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
