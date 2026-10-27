import Carbon.HIToolbox

/// A global shortcut through Carbon's `RegisterEventHotKey`, the only public API for one.
/// Defaults to ⌘Space, which only reaches us once Spotlight's own shortcut is turned off.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    /// False when the system refused the shortcut, for example because another app holds it.
    private(set) var isRegistered = false

    init(keyCode: Int = kVK_Space, modifiers: Int = cmdKey, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: 0x5350_5459, id: 1)  // "SPTY"
        let registered = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id,
                                             GetApplicationEventTarget(), 0, &ref)
        isRegistered = installed == noErr && registered == noErr
    }

    isolated deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
