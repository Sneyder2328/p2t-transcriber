import Foundation

private struct AWSAlternative: Codable { let Transcript: String }
private struct AWSResult: Codable { let Alternatives: [AWSAlternative]; let IsPartial: Bool }
private struct AWSTranscriptObj: Codable { let Results: [AWSResult] }
private struct AWSEvent: Codable { let Transcript: AWSTranscriptObj? }

final class TranscribeStreamer: NSObject {
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var accumulatedText: String = ""
    private var isOpen: Bool = false
    private var pendingChunks: [Data] = []
    private var negotiatedSampleRate: Int = 16000

    private func signer(region: String) -> TranscribeSigner { TranscribeSigner(region: region) }

    func start(languageCode: String, sampleRate: Int) {
        negotiatedSampleRate = sampleRate
        guard let creds = CredentialsStore.shared.load() else { return }

        var extras: [String: String] = [:]
        if PreferencesManager.shared.stabilization {
            extras["enable-partial-results-stabilization"] = "true"
            extras["partial-results-stability"] = PreferencesManager.shared.stabilityLevel
        }
        extras["sample-rate"] = String(sampleRate)

        let region = PreferencesManager.shared.region
        let s = signer(region: region)
        guard let url = s.presignWebsocketUrl(credentials: creds, languageCode: languageCode, extraParams: extras) else { return }
        if PreferencesManager.shared.logHandshakeURL { print("Presigned URL: \(url.absoluteString)") }

        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Origin": "https://transcribestreaming.\(region).amazonaws.com"
        ]
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
        let task = urlSession.webSocketTask(with: url, protocols: ["aws.transcribe"]) // negotiate subprotocol
        webSocket = task
        isOpen = false
        pendingChunks.removeAll()
        task.resume()
        listen()
    }

    func sendPcm(_ data: Data) {
        guard let webSocket else { return }
        if !isOpen {
            pendingChunks.append(data)
            return
        }
        webSocket.send(.data(data)) { error in
            if let error { print("ws send error: \(error)") }
        }
    }

    func stop(completion: @escaping (String?) -> Void) {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession.invalidateAndCancel()
        let text = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        accumulatedText = ""
        isOpen = false
        pendingChunks.removeAll()
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
                    self.handleTranscriptJSON(text: s)
                case .data(let d):
                    if let s = String(data: d, encoding: .utf8) { self.handleTranscriptJSON(text: s) }
                @unknown default:
                    break
                }
            }
            self.listen()
        }
    }

    private func handleTranscriptJSON(text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        if let event = try? decoder.decode(AWSEvent.self, from: data), let tr = event.Transcript {
            for result in tr.Results where result.IsPartial == false {
                if let alt = result.Alternatives.first, !alt.Transcript.isEmpty {
                    if !accumulatedText.isEmpty { accumulatedText += " " }
                    accumulatedText += alt.Transcript
                }
            }
        } else if PreferencesManager.shared.logHandshakeURL {
            print("ws raw: \(text)")
        }
    }
}

extension TranscribeStreamer: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol `protocol`: String?) {
        print("WebSocket opened, protocol=\(`protocol` ?? "nil")")
        isOpen = true
        while !pendingChunks.isEmpty {
            let chunk = pendingChunks.removeFirst()
            sendPcm(chunk)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        print("WebSocket closed: code=\(closeCode.rawValue) reason=\(reasonStr)")
        isOpen = false
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { print("WebSocket completed with error: \(error)") }
    }
}
