import Foundation
import Carbon

enum ModifierChoice: String, CaseIterable, Identifiable {
    case option, command, control, shift
    var id: String { rawValue }

    var carbonMask: UInt32 {
        switch self {
        case .option: return UInt32(optionKey)
        case .command: return UInt32(cmdKey)
        case .control: return UInt32(controlKey)
        case .shift: return UInt32(shiftKey)
        }
    }

    var displayName: String {
        switch self {
        case .option: return "Option (⌥)"
        case .command: return "Command (⌘)"
        case .control: return "Control (⌃)"
        case .shift: return "Shift (⇧)"
        }
    }
}

final class PreferencesManager {
    static let shared = PreferencesManager()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let languageCode = "prefs.languageCode"
        static let autoPaste = "prefs.autoPaste"
        static let modifierKey = "prefs.modifierKey"
        static let capitalize = "prefs.capitalize"
        static let stabilization = "prefs.stabilization"
        static let stabilityLevel = "prefs.stabilityLevel"
    }

    var languageCode: String {
        get { defaults.string(forKey: Keys.languageCode) ?? "en-US" }
        set { defaults.set(newValue, forKey: Keys.languageCode) }
    }

    var autoPaste: Bool {
        get { defaults.object(forKey: Keys.autoPaste) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.autoPaste) }
    }

    var modifierKey: ModifierChoice {
        get { ModifierChoice(rawValue: defaults.string(forKey: Keys.modifierKey) ?? "option") ?? .option }
        set { defaults.set(newValue.rawValue, forKey: Keys.modifierKey) }
    }

    var capitalize: Bool {
        get { defaults.object(forKey: Keys.capitalize) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.capitalize) }
    }

    var stabilization: Bool {
        get { defaults.object(forKey: Keys.stabilization) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.stabilization) }
    }

    var stabilityLevel: String {
        get { defaults.string(forKey: Keys.stabilityLevel) ?? "high" }
        set { defaults.set(newValue, forKey: Keys.stabilityLevel) }
    }
}
