import SwiftUI

/// Floating center controls: on/off for the current mode, follow speed, live state.
struct FloatingCenterBox: View {
    @ObservedObject var model: DebugModel
    let controller: AppController

    private var settings: FloatingCenterSettings { model.floatingCenterSettings }
    private var status: FloatingCenterStatus { model.engine.floatingCenter }
    private var mode: ControlMode { model.mode }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { model.floatingCenterSettings.isEnabled(for: model.mode) },
            set: { newValue in
                var updated = model.floatingCenterSettings
                updated.setEnabled(newValue, for: model.mode)
                controller.setFloatingCenterSettings(updated)
            })
    }

    private var followTimeBinding: Binding<Double> {
        Binding(
            get: { model.floatingCenterSettings.followTime },
            set: { newValue in
                var updated = model.floatingCenterSettings
                updated.followTime = newValue
                controller.setFloatingCenterSettings(updated)
            })
    }

    var body: some View {
        GroupBox(label: Text("Floating center")) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Center follows my head in \(mode.title) mode", isOn: enabledBinding)
                Text("When your head rests still near the center, the center slides to where your head is. It never moves while a direction is firing or held, or the pointer is moving. Each mode remembers its own on/off.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text("Follow time")
                        Spacer()
                        Text(String(format: "≈ %.1f s", settings.followTime))
                            .monospacedDigit()
                            .foregroundColor(.accentColor)
                    }
                    Slider(value: followTimeBinding, in: Config.FloatingCenter.followTimeRange, step: 0.1)
                    Text("How long the center takes to catch up with your resting head. Lower = follows faster.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(status.isFollowing ? Color.green : (status.enabled ? Color.orange : Color.gray))
                        .frame(width: 9, height: 9)
                    Text(status.state)
                        .font(.callout)
                }
                Text(String(format: "Center has moved %.1f° since the last calibration / recenter (ring on the Direction pad).",
                            status.shiftDegrees))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Snake's Turn log: every turn that fired (with its latency) and every turn that
/// was held back (with the reason). Newest at the top.
struct TurnLogView: View {
    let entries: [TurnLogEntry]

    var body: some View {
        GroupBox(label: Text("Turn log (newest first)")) {
            VStack(alignment: .leading, spacing: 2) {
                if entries.isEmpty {
                    Text("No turns yet.")
                        .foregroundColor(.secondary)
                }
                ForEach(entries) { entry in
                    HStack(alignment: .top, spacing: 6) {
                        Text(entry.fired ? "✓" : "✗")
                            .foregroundColor(entry.fired ? .green : .orange)
                        Text(entry.time)
                            .foregroundColor(.secondary)
                        Text(entry.text)
                            .foregroundColor(entry.fired ? .primary : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if let latency = entry.latencyMs {
                            Text(String(format: "%.0f ms", latency))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .font(.system(.caption, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
