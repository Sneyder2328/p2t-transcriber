import SwiftUI

struct ContentView: View {
    @StateObject private var ptt = PushToTalkViewModel()
    @State private var loginAtStart: Bool = LoginItemManager.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(ptt.isRecording ? Color.red : Color.gray)
                    .frame(width: 10, height: 10)
                Text(ptt.isRecording ? "Listening…" : "Idle")
                    .font(.headline)
                Spacer()
            }

            Button(action: {
                ptt.toggle()
            }) {
                Text(ptt.isRecording ? "Stop (\(PreferencesManager.shared.modifierKey.displayName))" : "Hold \(PreferencesManager.shared.modifierKey.displayName) to Talk")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("Language: \(PreferencesManager.shared.languageCode)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                if #available(macOS 14.0, *) {
                    SettingsLink { Text("Preferences…") }
                } else {
                    Button("Preferences…") {
                        if #available(macOS 13.0, *) {
                            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        } else {
                            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                        }
                    }
                }
                Spacer()
                Toggle("Start at login", isOn: $loginAtStart)
                    .toggleStyle(.switch)
                    .onChange(of: loginAtStart) { value in _ = LoginItemManager.setEnabled(value) }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(minWidth: 300)
        .onAppear { ptt.setupHotkey() }
    }
}

final class PushToTalkViewModel: ObservableObject {
    @Published var isRecording: Bool = false

    private let audio = AudioInputManager()
    private let transcriber = TranscribeStreamer()
    private let injector = TextInjector()

    func setupHotkey() {
        Hotkey.shared.updateModifier(PreferencesManager.shared.modifierKey)
        Hotkey.shared.registerDefault()
        Hotkey.shared.onPress = { [weak self] in self?.start() }
        Hotkey.shared.onRelease = { [weak self] in self?.stopAndDeliver() }
    }

    func toggle() {
        isRecording ? stopAndDeliver() : start()
    }

    func start() {
        guard !isRecording else { return }
        isRecording = true
        let language = PreferencesManager.shared.languageCode
        transcriber.start(languageCode: language)
        audio.startStreaming { [weak self] chunk in
            self?.transcriber.sendPcm(chunk)
        }
    }

    func stopAndDeliver() {
        guard isRecording else { return }
        isRecording = false
        audio.stop()
        transcriber.stop { [weak self] finalText in
            guard let self, var text = finalText, !text.isEmpty else { return }
            if PreferencesManager.shared.capitalize {
                text = Self.capitalizeSentences(text)
            }
            if PreferencesManager.shared.autoPaste {
                self.injector.paste(text: text)
            } else {
                self.injector.copyOnly(text: text)
            }
        }
    }

    private static func capitalizeSentences(_ input: String) -> String {
        var result = ""
        var capitalizeNext = true
        for char in input {
            if capitalizeNext {
                result.append(String(char).uppercased())
                capitalizeNext = false
            } else {
                result.append(char)
            }
            if char == "." || char == "!" || char == "?" { capitalizeNext = true }
        }
        return result
    }
}
