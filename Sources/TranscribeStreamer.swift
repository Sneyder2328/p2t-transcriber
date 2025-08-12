import Foundation

private struct AWSAlternative: Codable { let Transcript: String }
private struct AWSResult: Codable { let Alternatives: [AWSAlternative]; let IsPartial: Bool }
private struct AWSTranscriptObj: Codable { let Results: [AWSResult] }
private struct AWSEvent: Codable { let Transcript: AWSTranscriptObj? }

final class TranscribeStreamer: NSObject {
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var accumulatedText: String = ""

    private let signer = TranscribeSigner(region: "us-east-1")

    func start(languageCode: String) {
        guard let creds = CredentialsStore.shared.load() else { return }

        var extras: [String: String] = [:]
        if PreferencesManager.shared.stabilization {
            extras["enable-partial-results-stabilization"] = "true"
            extras["partial-results-stability"] = PreferencesManager.shared.stabilityLevel
        }

        guard let url = signer.presignWebsocketUrl(credentials: creds, languageCode: languageCode, extraParams: extras) else {
            return
        }
        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
        let task = urlSession.webSocketTask(with: url)
        webSocket = task
        task.resume()
        listen()
    }

    func sendPcm(_ data: Data) {
        webSocket?.send(.data(data)) { error in
            if let error { print("ws send error: \(error)") }
        }
    }

    func stop(completion: @escaping (String?) -> Void) {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession.invalidateAndCancel()
        let text = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        accumulatedText = ""
        completion(text)
    }

    private func listen() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                print("ws recv error: \(error)")
            case .success(let message):
                switch message {
                case .string(let s):
                    self.handleMessage(text: s)
                case .data(let d):
                    if let s = String(data: d, encoding: .utf8) {
                        self.handleMessage(text: s)
                    }
                @unknown default:
                    break
                }
            }
            self.listen()
        }
    }

    private func handleMessage(text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        if let event = try? decoder.decode(AWSEvent.self, from: data), let tr = event.Transcript {
            for result in tr.Results where result.IsPartial == false {
                if let alt = result.Alternatives.first {
                    if !alt.Transcript.isEmpty {
                        if !accumulatedText.isEmpty { accumulatedText += " " }
                        accumulatedText += alt.Transcript
                    }
                }
            }
        }
    }
}

extension TranscribeStreamer: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        // Connected
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        // Closed
    }
}
