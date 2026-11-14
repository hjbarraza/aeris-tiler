// Global hotkeys (what skhd did), through Carbon: no permission needed, and unlike skhd it
// reports the key release, which hold-to-resize needs.
import Carbon.HIToolbox
import TilerCore

final class Hotkeys {
    static let shared = Hotkeys()
    var handler: ((_ action: String, _ pressed: Bool) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var actions: [String] = []   // hotkey id -> action id
    private var installed = false

    /// Replace all hotkeys with these bindings (action id -> "ctrl+alt-left").
    func register(_ bindings: [String: String]) {
        unregister()
        install()
        for (action, spec) in bindings.sorted(by: { $0.key < $1.key }) {
            guard let combo = KeyCombo(spec) else { continue }
            var mods: UInt32 = 0
            for m in combo.mods { mods |= UInt32(["cmd": cmdKey, "shift": shiftKey, "alt": optionKey, "ctrl": controlKey][m]!) }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x4145_5253 /* AERS */, id: UInt32(actions.count))
            actions.append(action)
            if RegisterEventHotKey(combo.keyCode, mods, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref { refs.append(ref) }
        }
    }

    /// Release every hotkey (while the preferences window records a new one).
    func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = []
    }

    private func install() {
        guard !installed else { return }
        installed = true
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let me = Hotkeys.shared
            if Int(id.id) < me.actions.count { me.handler?(me.actions[Int(id.id)], GetEventKind(event) == UInt32(kEventHotKeyPressed)) }
            return noErr
        }, 2, &types, nil, nil)
    }
}
