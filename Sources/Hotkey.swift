import AppKit
import Carbon

final class Hotkey {
    static let shared = Hotkey()

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var isDown: Bool = false
    private var eventHandler: EventHandlerRef?
    private var modifierMask: UInt32 = PreferencesManager.shared.modifierKey.carbonMask

    private init() {}

    func registerDefault() {
        installEventHandler()
    }

    func updateModifier(_ choice: ModifierChoice) {
        modifierMask = choice.carbonMask
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventRawKeyModifiersChanged))
        let callback: EventHandlerUPP = { (next, event, userData) -> OSStatus in
            guard let userData else { return noErr }
            let unmanaged = Unmanaged<Hotkey>.fromOpaque(userData)
            let hotkey = unmanaged.takeUnretainedValue()
            var modifiers: UInt32 = 0
            GetEventParameter(event, UInt32(kEventParamKeyModifiers), UInt32(typeUInt32), nil, MemoryLayout<UInt32>.size, nil, &modifiers)

            let active = (modifiers & hotkey.modifierMask) != 0

            if active && !hotkey.isDown {
                hotkey.isDown = true
                hotkey.onPress?()
            } else if !active && hotkey.isDown {
                hotkey.isDown = false
                hotkey.onRelease?()
            }

            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), callback, 1, &eventType, selfPtr, &eventHandler)
    }
}
