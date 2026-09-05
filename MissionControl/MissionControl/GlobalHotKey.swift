//
//  GlobalHotKey.swift
//  MissionControl
//
//  A system-wide keyboard shortcut via Carbon's hot key API, which works inside the
//  App Sandbox and needs no Accessibility access.
//

import Carbon.HIToolbox

@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// `keyCode` is a Carbon virtual key code (e.g. `kVK_ANSI_M`); `modifiers` are Carbon
    /// modifier masks (`controlKey`, `optionKey`, `cmdKey`, `shiftKey`).
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                                  selfPointer, &handlerRef) == noErr else {
            return nil
        }

        let hotKeyID = EventHotKeyID(signature: 0x4D43_544C /* 'MCTL' */, id: 1)
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                  GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
