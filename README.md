# P2TTranscriber (Push-to-Talk Transcriber)

Menu bar app for macOS: hold Option to speak, on release it pastes the AWS Transcribe result into your current app.

## Build

- Requires macOS 13+, Xcode 15+, Swift 5.9
- Generate project: `xcodegen generate`
- Open `P2TTranscriber.xcodeproj` and run

## Permissions

- Microphone (prompt on first use)
- Accessibility: enable in System Settings → Privacy & Security → Accessibility, add P2TTranscriber to allow pasting keystrokes.

## AWS Credentials

Temporarily store your AWS keys in Keychain for local dev (App → menu will come in M2):

```bash
/usr/bin/security add-generic-password -a aws -s com.sneyder.p2t.credentials -w '{"accessKeyId":"AKIA...","secretAccessKey":"...","sessionToken":""}' -U
```

Alternatively, run the app once then use a pending settings window in M2 to enter keys.

## Hotkey

- Default: hold Option (⌥). Press and hold to talk; release to paste.

## Notes
- Uses AWS Transcribe Streaming WebSocket. Audio: 16 kHz, 16-bit PCM, mono.
- Language default: en-US (will be configurable later).
