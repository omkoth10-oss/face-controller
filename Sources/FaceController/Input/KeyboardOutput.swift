import CoreGraphics
import Foundation

/// Reasons key presses are currently not allowed. If ANY reason is present,
/// all held keys are released and new presses are refused.
enum InputBlockReason: String, CaseIterable, Hashable {
    case controlOff = "Control is OFF"
    case calibrating = "Calibrating"
    case noAccessibilityPermission = "Accessibility permission missing"
    case shuttingDown = "Quitting"
}

/// Sends real keyboard events to the whole system with CGEvent, and remembers
/// which keys are currently held so it can ALWAYS release them.
///
/// This class is the last line of defense against stuck keys:
/// - Every key press in the app goes through `press(_:)`.
/// - It refuses to press anything while there's a block reason (control off,
///   calibrating, no permission, quitting).
/// - Adding a block reason immediately releases every held key.
///
/// It's safe to call from any thread: a lock makes sure two threads never
/// change the held-keys list at the same time.
final class KeyboardOutput {

    private let lock = NSLock()
    private var heldKeys = Set<CGKeyCode>()
    private var blockReasons = Set<InputBlockReason>()

    /// `.hidSystemState` makes our events look like they came from a real keyboard.
    private let eventSource = CGEventSource(stateID: .hidSystemState)

    // MARK: - Pressing and releasing

    /// Presses (holds down) a key. Returns true if the key is now held.
    /// Returns false if pressing is blocked or the event couldn't be created.
    @discardableResult
    func press(_ key: CGKeyCode) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard blockReasons.isEmpty else { return false }
        if heldKeys.contains(key) { return true }
        guard post(key, keyDown: true) else { return false }
        heldKeys.insert(key)
        return true
    }

    /// Releases a key if we're holding it.
    func release(_ key: CGKeyCode) {
        lock.lock()
        defer { lock.unlock() }
        releaseLocked(key)
    }

    /// Releases every key we're holding. Returns how many keys were released.
    @discardableResult
    func releaseAll() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return releaseAllLocked()
    }

    // MARK: - Blocking

    /// Adds or removes a reason that blocks key presses.
    /// Adding a reason releases all held keys right away.
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

    func isHeld(_ key: CGKeyCode) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return heldKeys.contains(key)
    }

    var hasHeldKeys: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !heldKeys.isEmpty
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
        let keys = heldKeys
        for key in keys {
            releaseLocked(key)
        }
        return keys.count
    }

    private func releaseLocked(_ key: CGKeyCode) {
        guard heldKeys.contains(key) else { return }
        // Try twice. If both attempts fail (extremely unlikely), keep the key in
        // the list so the next release attempt (watchdog, kill switch, quit) retries.
        if post(key, keyDown: false) || post(key, keyDown: false) {
            heldKeys.remove(key)
        }
    }

    /// Creates one keyboard event and posts it at the HID level (where real
    /// keyboard events enter the system), so games see it like a real key.
    private func post(_ key: CGKeyCode, keyDown: Bool) -> Bool {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: keyDown) else {
            return false
        }
        // No modifier keys. Without this, a Space press while you happen to hold
        // Command could become Command+Space (Spotlight).
        event.flags = []
        event.post(tap: .cghidEventTap)
        return true
    }
}
