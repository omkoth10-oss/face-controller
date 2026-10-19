import CoreGraphics
import Carbon.HIToolbox  // Arrow key codes.
import Foundation

/// Something the app can press and hold.
enum OutputAction: Hashable {
    case key(CGKeyCode)
    case leftMouseButton
}

/// Reasons input is currently not allowed. If ANY reason is present, every held
/// key/button is released, presses are refused and the mouse can't be moved.
enum InputBlockReason: String, CaseIterable, Hashable {
    case controlOff = "Control is OFF"
    case calibrating = "Calibrating"
    case noAccessibilityPermission = "Accessibility permission missing"
    case shuttingDown = "Quitting"
}

/// Sends real keyboard and mouse events to the whole system with CGEvent, and
/// remembers what's held down so it can ALWAYS release it.
///
/// This class is the last line of defense against stuck keys and runaway mice:
/// - Every key press, mouse click and mouse movement in the app goes through here.
/// - Nothing is sent while there's a block reason (control off, calibrating,
///   no permission, quitting).
/// - Adding a block reason immediately releases everything that's held.
///
/// It's safe to call from any thread: a lock makes sure two threads never change
/// the state at the same time.
final class VirtualInput {

    private let lock = NSLock()
    private var held = Set<OutputAction>()
    private var blockReasons = Set<InputBlockReason>()

    /// `.hidSystemState` makes our events look like they came from real hardware.
    private let eventSource = CGEventSource(stateID: .hidSystemState)

    /// Releases the key at the end of a tap.
    private let tapQueue = DispatchQueue(label: "FaceController.tap-release", qos: .userInteractive)

    // MARK: - Press / release / tap

    /// Presses (holds down) a key or mouse button. Returns true if it's now held.
    /// Returns false if input is blocked or the event couldn't be created.
    @discardableResult
    func press(_ action: OutputAction) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard blockReasons.isEmpty else { return false }
        if held.contains(action) { return true }
        guard post(action, down: true) else { return false }
        held.insert(action)
        return true
    }

    /// Releases a key or mouse button if we're holding it.
    func release(_ action: OutputAction) {
        lock.lock()
        defer { lock.unlock() }
        releaseLocked(action)
    }

    /// One quick press: down now, up automatically after `duration` seconds.
    /// (Some games miss a press that's released in the same instant.)
    @discardableResult
    func tap(_ action: OutputAction, duration: Double) -> Bool {
        guard press(action) else { return false }
        tapQueue.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.release(action)
        }
        return true
    }

    /// Releases everything we're holding. Returns how many things were released.
    @discardableResult
    func releaseAll() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return releaseAllLocked()
    }

    // MARK: - Mouse movement

    /// Moves the mouse pointer by (dx, dy) screen points (+x = right, +y = down).
    /// Refused while input is blocked.
    ///
    /// We send BOTH a new pointer position and the movement amount ("delta").
    /// Desktop apps follow the position; games that lock the pointer (first-person
    /// cameras, e.g. Minecraft) ignore the position and read only the delta.
    @discardableResult
    func moveMouse(dx: Int, dy: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard blockReasons.isEmpty, dx != 0 || dy != 0 else { return false }

        let current = Self.currentMouseLocation()
        let proposed = CGPoint(x: current.x + CGFloat(dx), y: current.y + CGFloat(dy))
        let target = Self.keepOnScreen(proposed, from: current)

        // While the left button is held, macOS calls movement "dragging".
        let type: CGEventType = held.contains(.leftMouseButton) ? .leftMouseDragged : .mouseMoved
        guard let event = CGEvent(mouseEventSource: eventSource,
                                  mouseType: type,
                                  mouseCursorPosition: target,
                                  mouseButton: .left) else { return false }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        event.flags = []
        event.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - Blocking

    /// Adds or removes a reason that blocks input.
    /// Adding a reason releases everything held right away.
    func setBlocked(_ reason: InputBlockReason, _ blocked: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if blocked {
            blockReasons.insert(reason)
            releaseAllLocked()
        } else {
            blockReasons.remove(reason)
        }
    }

    // MARK: - Reading state

    func isHeld(_ action: OutputAction) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return held.contains(action)
    }

    var hasHeldOutputs: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !held.isEmpty
    }

    var isBlocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !blockReasons.isEmpty
    }

    var currentBlockReasons: [InputBlockReason] {
        lock.lock()
        defer { lock.unlock() }
        // Keep a stable order for display.
        return InputBlockReason.allCases.filter { blockReasons.contains($0) }
    }

    // MARK: - Private (lock must already be held)

    @discardableResult
    private func releaseAllLocked() -> Int {
        let actions = held
        for action in actions {
            releaseLocked(action)
        }
        return actions.count
    }

    private func releaseLocked(_ action: OutputAction) {
        guard held.contains(action) else { return }
        // Try twice. If both attempts fail (extremely unlikely), keep it in the list
        // so the next release attempt (watchdog, kill switch, quit) retries.
        if post(action, down: false) || post(action, down: false) {
            held.remove(action)
        }
    }

    private func post(_ action: OutputAction, down: Bool) -> Bool {
        switch action {
        case .key(let key):
            return postKey(key, down: down)
        case .leftMouseButton:
            return postLeftButton(down: down)
        }
    }

    /// Creates one keyboard event and posts it at the HID level (where real
    /// keyboard events enter the system), so games see it like a real key.
    private func postKey(_ key: CGKeyCode, down: Bool) -> Bool {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: down) else {
            return false
        }
        // No modifier keys, so e.g. Space can't turn into Command+Space (Spotlight)
        // if you happen to hold Command. Real arrow keys always carry the
        // "function key" and "numeric pad" flags, so we add those for arrows.
        event.flags = Self.isArrowKey(key) ? [.maskSecondaryFn, .maskNumericPad] : []
        event.post(tap: .cghidEventTap)
        return true
    }

    private func postLeftButton(down: Bool) -> Bool {
        guard let event = CGEvent(mouseEventSource: eventSource,
                                  mouseType: down ? .leftMouseDown : .leftMouseUp,
                                  mouseCursorPosition: Self.currentMouseLocation(),
                                  mouseButton: .left) else { return false }
        event.setIntegerValueField(.mouseEventClickState, value: 1)  // A single click.
        event.flags = []
        event.post(tap: .cghidEventTap)
        return true
    }

    private static func isArrowKey(_ key: CGKeyCode) -> Bool {
        [kVK_LeftArrow, kVK_RightArrow, kVK_DownArrow, kVK_UpArrow].contains(Int(key))
    }

    // MARK: - Screen helpers

    /// Where the pointer is now (top-left origin, in points).
    private static func currentMouseLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Keeps the pointer on a screen: if the new position isn't on any display,
    /// clamp it to the edges of the display it's on now.
    private static func keepOnScreen(_ point: CGPoint, from current: CGPoint) -> CGPoint {
        if display(containing: point) != nil { return point }
        let bounds = display(containing: current).map { CGDisplayBounds($0) } ?? CGDisplayBounds(CGMainDisplayID())
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX - 1),
                       y: min(max(point.y, bounds.minY), bounds.maxY - 1))
    }

    private static func display(containing point: CGPoint) -> CGDirectDisplayID? {
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        let error = CGGetDisplaysWithPoint(point, 1, &displayID, &count)
        return (error == .success && count > 0) ? displayID : nil
    }
}
