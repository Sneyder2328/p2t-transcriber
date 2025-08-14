import AppKit
import Carbon
import ApplicationServices

final class Hotkey {
    static let shared = Hotkey()

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var isDown: Bool = false
    private var eventHandler: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let requiredModifiersMask: UInt32 = UInt32(cmdKey | controlKey)

    private init() {}

    func registerDefault() {
        installGlobalTap()
    }

    func updateModifier(_ choice: ModifierChoice) {
        // No-op: using explicit Command+H
    }

    private func installGlobalTap() {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let hotkey = Unmanaged<Hotkey>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = hotkey.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let flags = event.flags
            let active = flags.contains(.maskCommand) && flags.contains(.maskControl)
            if active && !hotkey.isDown {
                hotkey.isDown = true
                hotkey.onPress?()
            } else if !active && hotkey.isDown {
                hotkey.isDown = false
                hotkey.onRelease?()
            }
            return Unmanaged.passUnretained(event)
        }
        if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: selfPtr) {
            eventTap = tap
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            runLoopSource = src
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            // Fallback to app-only modifiers if global tap fails
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventRawKeyModifiersChanged))
            let carbonCallback: EventHandlerUPP = { (next, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                let unmanaged = Unmanaged<Hotkey>.fromOpaque(userData)
                let hotkey = unmanaged.takeUnretainedValue()
                var modifiers: UInt32 = 0
                GetEventParameter(event, UInt32(kEventParamKeyModifiers), UInt32(typeUInt32), nil, MemoryLayout<UInt32>.size, nil, &modifiers)
                let active = (modifiers & hotkey.requiredModifiersMask) == hotkey.requiredModifiersMask
                if active && !hotkey.isDown {
                    hotkey.isDown = true
                    hotkey.onPress?()
                } else if !active && hotkey.isDown {
                    hotkey.isDown = false
                    hotkey.onRelease?()
                }
                return noErr
            }
            InstallEventHandler(GetEventDispatcherTarget(), carbonCallback, 1, &eventType, selfPtr, &eventHandler)
        }
    }
}
