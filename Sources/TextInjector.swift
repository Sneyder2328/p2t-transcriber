import AppKit
import Carbon

final class TextInjector {
    func type(text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        var utf16 = Array(text.utf16)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(0), keyDown: true)
        keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(0), keyDown: false)
        keyUp?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    func paste(text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Keep the result on the clipboard so user can see it or paste manually
        // If we had a previous value, store it under a different type would be complex; skip restoring
    }

    func copyOnly(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
