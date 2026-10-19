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

/// Snake's Turn log, newest at the top:
/// - ✓ turns that fired (with latency, and how far the head went once it's back),
/// - RED: turns that were held back or not sent, with the exact reason,
/// - ORANGE: small flicks the extra-turn guard ignored as side effects of another movement.
struct TurnLogView: View {
    let entries: [TurnLogEntry]

    private var blockedCount: Int { entries.filter { !$0.fired && !$0.ignoredExtra }.count }
    private var ignoredCount: Int { entries.filter { $0.ignoredExtra }.count }

    var body: some View {
        GroupBox(label: Text("Turn log (newest first)")) {
            VStack(alignment: .leading, spacing: 3) {
                if entries.isEmpty {
                    Text("No turns yet.")
                        .foregroundColor(.secondary)
                }
                if blockedCount > 0 {
                    Text("\(blockedCount) of the last \(entries.count) lines: a turn did NOT go through (red).")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                }
                if ignoredCount > 0 {
                    Text("\(ignoredCount) ignored as extra turns (orange). If one was a turn you wanted, tell me.")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                }
                ForEach(entries) { entry in
                    row(entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func row(_ entry: TurnLogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.fired ? "✓" : "✗")
                .font(.system(.callout, design: .monospaced).bold())
                .foregroundColor(entry.fired ? .green : .white)
            Text(entry.time)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(entry.fired ? .secondary : .white)
            (Text(entry.text) + reachedText(entry))
                .font(.system(.callout, design: .monospaced))
                .fontWeight(entry.fired ? .regular : .bold)
                .foregroundColor(entry.fired ? .primary : .white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let latency = entry.latencyMs {
                Text(String(format: "%.0f ms", latency))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(rowColor(entry))
        .cornerRadius(4)
    }

    private func rowColor(_ entry: TurnLogEntry) -> Color {
        if entry.fired { return .clear }
        return entry.ignoredExtra ? Color.orange.opacity(0.85) : Color.red.opacity(0.85)
    }

    /// "· head went to 13°" once the turn's movement is over. Real turns usually go
    /// well past the press threshold; an extra turn barely makes it.
    private func reachedText(_ entry: TurnLogEntry) -> Text {
        guard let reached = entry.reachedDegrees else { return Text("") }
        return Text(String(format: " · head went to %.0f°", reached))
            .foregroundColor(.secondary)
    }
}
