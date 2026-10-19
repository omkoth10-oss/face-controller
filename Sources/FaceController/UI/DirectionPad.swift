import SwiftUI

/// Shows which way the app thinks you're moving your head, from YOUR point of view.
///
/// The dot moves like your head: turn to your left and it goes left, tilt up and
/// it goes up. If it ever moves the opposite way, the direction is wrong for this
/// camera: flip it in Config.Directions.
struct DirectionPad: View {
    let offset: PlayerHeadOffset?
    let mode: ControlMode

    /// Degrees from neutral shown at the edge of the pad.
    private let range: Double = 20
    private let size: CGFloat = 150

    /// Where the dashed box is: the press thresholds (Keys/Snake) or the deadzone (Aim).
    private var boxHalfWidth: Double {
        switch mode {
        case .keys: return Config.Gestures.turnLeft.press
        case .aim: return Config.Aim.horizontalDeadzone
        case .snake: return Config.Snake.pressDegrees
        }
    }

    private var boxHalfHeight: Double {
        switch mode {
        case .keys: return Config.Gestures.tiltUp.press
        case .aim: return Config.Aim.verticalDeadzone
        case .snake: return Config.Snake.pressDegrees
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.12))
                Rectangle()
                    .fill(Color.gray.opacity(0.35))
                    .frame(width: 1, height: size)
                Rectangle()
                    .fill(Color.gray.opacity(0.35))
                    .frame(width: size, height: 1)
                Rectangle()
                    .stroke(Color.orange.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: scaled(boxHalfWidth) * 2, height: scaled(boxHalfHeight) * 2)

                label("UP", lit: isUp).offset(y: -size / 2 + 10)
                label("DOWN", lit: isDown).offset(y: size / 2 - 10)
                label("LEFT", lit: isLeft).offset(x: -size / 2 + 18)
                label("RIGHT", lit: isRight).offset(x: size / 2 - 20)

                if let offset = offset {
                    Circle()
                        .fill(isCentered ? Color.blue : Color.green)
                        .frame(width: 14, height: 14)
                        // Your left = screen left (negative x); up = screen up (negative y).
                        .offset(x: clamped(-offset.left), y: clamped(-offset.up))
                }
            }
            .frame(width: size, height: size)

            Text(directionText)
                .font(.headline)
            Text("Should match YOUR head. Backwards? Set flipHorizontal / flipVertical in Config.swift.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Direction logic

    private var isLeft: Bool { (offset?.left ?? 0) > boxHalfWidth }
    private var isRight: Bool { (offset?.left ?? 0) < -boxHalfWidth }
    private var isUp: Bool { (offset?.up ?? 0) > boxHalfHeight }
    private var isDown: Bool { (offset?.up ?? 0) < -boxHalfHeight }
    private var isCentered: Bool { !isLeft && !isRight && !isUp && !isDown }

    private var directionText: String {
        guard offset != nil else { return "Direction: no face" }
        var parts: [String] = []
        if isUp { parts.append("UP") }
        if isDown { parts.append("DOWN") }
        if isLeft { parts.append("LEFT") }
        if isRight { parts.append("RIGHT") }
        return "Direction: " + (parts.isEmpty ? "CENTER" : parts.joined(separator: " + "))
    }

    // MARK: - Drawing helpers

    private func scaled(_ degrees: Double) -> CGFloat {
        CGFloat(min(degrees, range) / range) * size / 2
    }

    private func clamped(_ degrees: Double) -> CGFloat {
        CGFloat(min(max(degrees, -range), range) / range) * (size / 2 - 8)
    }

    private func label(_ text: String, lit: Bool) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundColor(lit ? .green : .secondary)
    }
}
