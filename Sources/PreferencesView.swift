import SwiftUI

struct PreferencesView: View {
    @State private var languageCode: String = PreferencesManager.shared.languageCode
    @State private var modifier: ModifierChoice = PreferencesManager.shared.modifierKey
    @State private var autoPaste: Bool = PreferencesManager.shared.autoPaste
    @State private var capitalize: Bool = PreferencesManager.shared.capitalize
    @State private var stabilization: Bool = PreferencesManager.shared.stabilization
    @State private var stabilityLevel: String = PreferencesManager.shared.stabilityLevel

    @State private var accessKeyId: String = ""
    @State private var secretAccessKey: String = ""
    @State private var sessionToken: String = ""

    @State private var loginAtStart: Bool = LoginItemManager.isEnabled
    @State private var savedBanner: String? = nil

    private let languages: [String] = [
        "en-US","es-US","es-ES","es-MX","fr-FR","de-DE","it-IT","pt-BR","ja-JP"
    ]

    var body: some View {
        TabView {
            Form {
                Picker("Language", selection: $languageCode) {
                    ForEach(languages, id: \.self) { Text($0) }
                }
                Picker("Hold modifier", selection: $modifier) {
                    ForEach(ModifierChoice.allCases) { m in Text(m.displayName).tag(m) }
                }
                Toggle("Auto paste on release", isOn: $autoPaste)
                Toggle("Capitalize sentences", isOn: $capitalize)
                Toggle("Stabilize partial results", isOn: $stabilization)
                if stabilization {
                    Picker("Stability level", selection: $stabilityLevel) {
                        Text("low").tag("low"); Text("medium").tag("medium"); Text("high").tag("high")
                    }
                }
                Toggle("Start at login", isOn: $loginAtStart)
                    .onChange(of: loginAtStart) { val in _ = LoginItemManager.setEnabled(val) }
            }
            .padding()
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                SecureField("Secret Access Key", text: $secretAccessKey)
                TextField("Access Key ID", text: $accessKeyId)
                TextField("Session Token (optional)", text: $sessionToken)
                HStack {
                    Spacer()
                    Button("Save Credentials") { saveCreds() }
                }
                if let savedBanner { Text(savedBanner).font(.caption).foregroundStyle(.secondary) }
            }
            .padding()
            .onAppear { loadCreds() }
            .tabItem { Label("AWS", systemImage: "key.fill") }
        }
        .frame(width: 460, height: 360)
        .onDisappear { persist() }
    }

    private func persist() {
        PreferencesManager.shared.languageCode = languageCode
        PreferencesManager.shared.modifierKey = modifier
        PreferencesManager.shared.autoPaste = autoPaste
        PreferencesManager.shared.capitalize = capitalize
        PreferencesManager.shared.stabilization = stabilization
        PreferencesManager.shared.stabilityLevel = stabilityLevel
        Hotkey.shared.updateModifier(modifier)
    }

    private func loadCreds() {
        if let c = CredentialsStore.shared.load() {
            accessKeyId = c.accessKeyId
            secretAccessKey = c.secretAccessKey
            sessionToken = c.sessionToken ?? ""
        }
    }

    private func saveCreds() {
        guard !accessKeyId.isEmpty, !secretAccessKey.isEmpty else {
            savedBanner = "Please enter Access Key ID and Secret Key"; return
        }
        CredentialsStore.shared.save(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, sessionToken: sessionToken.isEmpty ? nil : sessionToken)
        savedBanner = "Saved to Keychain"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedBanner = nil }
    }
}
