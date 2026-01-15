import Cocoa
import Carbon.HIToolbox

struct HotKey {
    let keyCode: UInt32     // kVK_...
    let modifiers: UInt32   // cmdKey, optionKey, controlKey, shiftKey

    static let command: UInt32 = UInt32(cmdKey)
    static let option: UInt32  = UInt32(optionKey)
    static let control: UInt32 = UInt32(controlKey)
    static let shift: UInt32   = UInt32(shiftKey)
    /// All four modifiers: command + option + control + shift
    static let hyper: UInt32 = command | option | control | shift

    /// Convenience for Command+Option+Control+Shift + Keypad '.'
    static func keypadDot() -> HotKey {
        return HotKey(keyCode: UInt32(kVK_ANSI_KeypadDecimal), modifiers: hyper)
    }
    /// Convenience for Command + ';'
    static func commandSemicolon() -> HotKey {
        return HotKey(keyCode: UInt32(kVK_ANSI_Semicolon), modifiers: command)
    }
}

/// A simple global hotkey manager based on Carbon's RegisterEventHotKey.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    deinit {
        unregister()
    }

    @discardableResult
    func register(hotKey: HotKey, handler: @escaping () -> Void) -> Bool {
        unregister()

        self.handler = handler

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { (_, _, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let unmanaged = Unmanaged<HotKeyManager>.fromOpaque(userData)
            let manager = unmanaged.takeUnretainedValue()
            manager.handler?()
            return noErr
        }

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetEventDispatcherTarget(), callback, 1, &eventSpec, userData, &eventHandlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x484B4D47), id: UInt32(1)) // 'HKMG'
        let status = RegisterEventHotKey(hotKey.keyCode,
                                         hotKey.modifiers,
                                         hotKeyID,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &hotKeyRef)
        if status != noErr {
            NSLog("Failed to register hotkey: \(status)")
            return false
        }

        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handlerRef = eventHandlerRef {
            RemoveEventHandler(handlerRef)
            eventHandlerRef = nil
        }
        handler = nil
    }
}

