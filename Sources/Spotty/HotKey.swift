import Carbon.HIToolbox
import LauncherCore

/// A global shortcut through Carbon's `RegisterEventHotKey`, the only public API for one.
/// Defaults to ⌘Space, which only reaches us once Spotlight's own shortcut is turned off.
/// Holding the shortcut acts once: presses only count after a release.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private var gate = PressGate()
    /// False when the system refused the shortcut, for example because another app holds it.
    private(set) var isRegistered = false

    init(keyCode: Int = kVK_Space, modifiers: Int = cmdKey, action: @escaping () -> Void) {
        self.action = action
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            MainActor.assumeIsolated { pressed ? hotKey.pressed() : hotKey.gate.release() }
            return noErr
        }, specs.count, &specs, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: 0x5350_5459, id: 1)  // "SPTY"
        let registered = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id,
                                             GetApplicationEventTarget(), 0, &ref)
        isRegistered = installed == noErr && registered == noErr
    }

    private func pressed() {
        guard gate.press() else {
            debugNote("hotkey repeat ignored")
            return
        }
        debugNote("hotkey")
        action()
    }

    isolated deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
