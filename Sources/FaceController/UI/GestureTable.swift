import SwiftUI

/// Every gesture: what it does in this mode, its live value, its thresholds,
/// and whether it's firing right now.
struct GestureTable: View {
    let gestures: [GestureSnapshot]
    let mode: ControlMode
    let isSnake: Bool

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                Text("Gesture")
                Text("Does")
                Text("Live value")
                Text("Press / release")
                Text("Status")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            ForEach(gestures) { row in
                GridRow {
                    Text(row.gesture.displayName)
                    Text(row.binding?.description ?? "off")
                        .foregroundColor(row.binding == nil ? .secondary : .primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DisplayFormat.gestureValue(row.value, unit: row.gesture.unit))
                            .monospacedDigit()
                        ThresholdBar(value: row.value,
                                     pressThreshold: row.thresholds.press,
                                     releaseThreshold: row.thresholds.release,
                                     isFiring: row.firing)
                            .frame(width: 90, height: 8)
                    }
                    Text("\(DisplayFormat.threshold(row.thresholds.press, unit: row.gesture.unit)) / \(DisplayFormat.threshold(row.thresholds.release, unit: row.gesture.unit))")
                        .font(.caption)
                        .monospacedDigit()
                    status(for: row)
                }
                .opacity(row.binding == nil ? 0.45 : 1)
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private func status(for row: GestureSnapshot) -> some View {
        if row.binding == nil {
            Text("off in \(mode.title)")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if row.firing {
            Pill(text: row.binding?.style == .tap ? "TAP" : "HELD", color: .green)
        } else {
            Text(phaseText(row.phase))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func phaseText(_ phase: GesturePhase) -> String {
        switch phase {
        case .waitingForNeutral:
            return isSnake ? "re-arming (come back)" : "back to neutral"
        case .ready:
            return "ready"
        case .holding(let progress):
            return "hold… \(Int(progress * 100))%"
        case .active:
            return "fired"
        }
    }
}
