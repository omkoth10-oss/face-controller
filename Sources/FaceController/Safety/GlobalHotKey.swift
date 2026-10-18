import Carbon.HIToolbox

/// A system-wide keyboard shortcut (works even when a game is focused / full screen).
///
/// It uses Carbon's `RegisterEventHotKey`, the long-standing macOS API for global
/// hotkeys. Nice properties:
/// - Needs NO extra permission (not Accessibility, not Input Monitoring).
/// - The shortcut is "consumed": the focused game never sees it.
///
/// Carbon is a C API, so the callback is a C function. We pass a pointer to this
/// object through `userData` so the C callback can find its way back to Swift.
final class GlobalHotKey {

    /// Four-letter tag ("FCTL") so we only react to OUR hotkey.
    private static let signature: OSType = 0x4643_544C

    private let hotKeyID: EventHotKeyID
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Registers the shortcut. Returns nil if it couldn't be registered
    /// (for example, another app already owns this exact shortcut).
    /// `action` runs on the main thread.
    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32 = 1, action: @escaping () -> Void) {
        self.hotKeyID = EventHotKeyID(signature: GlobalHotKey.signature, id: id)
        self.action = action

        // 1. Listen for "a hotkey was pressed" events sent to this app.
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                // This closure is a plain C function: it can't capture Swift variables.
                guard let event = event, let userData = userData else {
                    return OSStatus(eventNotHandledErr)
                }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                return hotKey.handle(event)
            },
            1,
            &eventType,
            userData,
            &handlerRef)
        guard installStatus == noErr else { return nil }  // deinit cleans up.

        // 2. Ask macOS to send us that event when our key combination is pressed.
        let registerStatus = RegisterEventHotKey(keyCode,
                                                 modifiers,
                                                 hotKeyID,
                                                 GetApplicationEventTarget(),
                                                 0,
                                                 &hotKeyRef)
        guard registerStatus == noErr else { return nil }  // deinit cleans up.
    }

    deinit {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef = handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var pressedID = EventHotKeyID()
        let status = GetEventParameter(event,
                                       EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID),
                                       nil,
                                       MemoryLayout<EventHotKeyID>.size,
                                       nil,
                                       &pressedID)
        guard status == noErr else { return status }
        guard pressedID.signature == hotKeyID.signature, pressedID.id == hotKeyID.id else {
            return OSStatus(eventNotHandledErr)  // Someone else's hotkey.
        }
        action()
        return noErr
    }
}
