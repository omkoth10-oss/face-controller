import AppKit
import SwiftUI

/// A small label that floats at the top of the screen, over the game, showing what
/// the head is doing (MOVE / AIM) and what's held. Shown in the Minecraft preset,
/// so you don't have to look at the debug window while playing.
///
/// The tricky part: it must NEVER take the keyboard or mouse from the game.
/// - `.nonactivatingPanel`: showing it doesn't make our app the active app.
/// - `ignoresMouseEvents`: clicks go straight through it to the game.
/// - `.canJoinAllSpaces` + `.fullScreenAuxiliary`: it also appears over a
///   full-screen browser or game.
/// Use from the main thread only.
final class GameOverlay {
    private let panel: NSPanel

    init(model: DebugModel) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 90),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: GameOverlayView(model: model))
    }

    func setVisible(_ visible: Bool) {
        if visible {
            guard !panel.isVisible else { return }
            placeAtTopCenter()
            panel.orderFrontRegardless()  // Shows it without activating our app.
        } else {
            panel.orderOut(nil)
        }
    }

    private func placeAtTopCenter() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - 6))
    }
}

/// What the overlay shows.
struct GameOverlayView: View {
    @ObservedObject var model: DebugModel

    private var status: MinecraftStatus { model.engine.minecraft }

    /// Labels of everything held right now (e.g. "W", "Space").
    private var heldLabels: [String] {
        model.engine.gestures.compactMap { row in
            guard row.firing, let binding = row.binding, binding.style == .hold else { return nil }
            return binding.label
        }
    }

    private var title: String {
        if !model.controlEnabled { return "OFF" }
        switch status.option {
        case .modeSwitch:
            return status.headJob.title
        case .faceMoves:
            return "AIM"
        case .splitZones:
            return heldLabels.contains(where: { ["W", "A", "S", "D"].contains($0) }) ? "AIM + WALK" : "AIM"
        }
    }

    private var titleColor: Color {
        if !model.controlEnabled { return .red }
        if status.option == .modeSwitch && status.headJob == .move { return .green }
        return Color(red: 0.35, green: 0.7, blue: 1.0)
    }

    private var detail: String {
        if !model.controlEnabled { return "Turn on: \(Config.Safety.killSwitchDescription)" }
        if !model.engine.faceVisible { return "No face: look at the camera" }
        if status.headPaused { return "Head tilted: switching…" }
        let held = heldLabels.isEmpty ? "nothing held" : "held: " + heldLabels.joined(separator: " + ")
        switch status.option {
        case .faceMoves: return "mouth walks · brows jump · \(held)"
        case .modeSwitch: return "tilt to a shoulder to switch · \(held)"
        case .splitZones: return "turn far to walk · \(held)"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(titleColor)
            Text(detail)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.65)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
