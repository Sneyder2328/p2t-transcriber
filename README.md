# P2TTranscriber (Push‑to‑Talk Transcriber)

Menu bar app for macOS: hold Control+Command to speak, then on release it types the AWS Transcribe result into your current app and also copies it to the clipboard.

## Features

- **Push‑to‑talk**: Hold ⌃⌘ to start/stop live transcription
- **Types into the focused app**: Injects the recognized text as keystrokes for a native feel; also keeps the text on the clipboard
- **Configurable**: Region, language, capitalization, start at login
- **Low‑latency audio**: 16 kHz, 16‑bit PCM, mono

## Requirements

- macOS 13+
- Xcode 15+
- Swift 5.9
- An AWS account with permission to use Transcribe Streaming

## Build

1. Install XcodeGen (if you don’t already have it): `brew install xcodegen`
2. Generate the Xcode project: `xcodegen generate`
3. Open `P2TTranscriber.xcodeproj` and Run

Packages are fetched via Swift Package Manager on first build. The project depends on the AWS SDK for Swift (`AWSTranscribeStreaming`, `AWSClientRuntime`).

## Permissions

- **Microphone**: Prompted on first use.
- **Accessibility**: Required to type keystrokes into other apps. Enable in System Settings → Privacy & Security → Accessibility, then allow `P2TTranscriber`.

## AWS Credentials

This app currently uses the AWS SDK for Swift’s default credential provider chain. Provide credentials using any of the standard methods:

- **Environment variables**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, optionally `AWS_SESSION_TOKEN`
- **Shared config/credentials files**: `~/.aws/config` and `~/.aws/credentials` (you can also set `AWS_PROFILE`)
- **Other providers** supported by the SDK (SSO, etc.)

Optional (experimental / for future WebSocket mode): You can store keys in the macOS Keychain under service `com.sneyder.p2t.credentials` and account `aws`. For convenience:

```bash
/usr/bin/security add-generic-password -a aws -s com.sneyder.p2t.credentials -w '{"accessKeyId":"AKIA...","secretAccessKey":"...","sessionToken":""}' -U
```

There is also an AWS tab in Preferences that writes these values to Keychain. Note: the SDK‑based transcriber path uses the default provider chain; the Keychain values are reserved for an alternative WebSocket path.

## Usage

1. Launch the app; it appears as a mic icon in the menu bar.
2. On first use, grant Microphone and Accessibility permissions when prompted.
3. Open Preferences from the menu bar window to set:
   - **Region** (default `us-east-1`)
   - **Language** (default `en-US`)
   - **Capitalize sentences**
   - **Start at login**
4. Hold **Control (⌃) + Command (⌘)** to talk; release to insert the recognized text into the active app. The text also remains on the clipboard.

## Hotkey

- Default and currently fixed: **hold Control (⌃) + Command (⌘)** to talk. Custom hotkey UI exists but is not yet wired to the global detector.

## Languages

Commonly used codes (subset): `en-US`, `es-US`, `es-ES`, `es-MX`, `fr-FR`, `de-DE`, `it-IT`, `pt-BR`, `ja-JP`.

## Notes

- Uses AWS Transcribe Streaming via the AWS SDK for Swift.
- Audio format: 16 kHz, 16‑bit PCM, mono.
- Result text is typed into the current app and also copied to the clipboard.

## Troubleshooting

- **No text is inserted**: Ensure Accessibility permission is granted to `P2TTranscriber`. Some apps may restrict simulated typing—use the clipboard as a fallback.
- **Credential/permission errors**: Verify your AWS credentials are available via the default provider chain and that the selected region supports your language.
- **Microphone access denied**: Re‑enable Mic permission in System Settings → Privacy & Security → Microphone.
- **Nothing happens when holding ⌃⌘**: Make sure the menu bar app is running and accessible; try toggling Accessibility permission off/on.

## Roadmap

- Customizable push‑to‑talk modifier
- Switchable SDK/WebSocket backends and Keychain credential provider
- Additional language presets and per‑app behavior

