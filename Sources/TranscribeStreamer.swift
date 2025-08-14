import Foundation

private struct AWSAlternative: Codable { let Transcript: String }
private struct AWSResult: Codable { let Alternatives: [AWSAlternative]; let IsPartial: Bool }
private struct AWSTranscriptObj: Codable { let Results: [AWSResult] }
private struct AWSTranscriptEnvelope: Codable { let Transcript: AWSTranscriptObj? }

final class TranscribeStreamer: NSObject {
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var accumulatedText: String = ""
    private var isOpen: Bool = false
    private var pendingChunks: [Data] = []
    private var negotiatedSampleRate: Int = 16000
    private var incomingBuffer = Data()

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
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
        var request = URLRequest(url: url)
        request.setValue("aws.transcribe", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        request.setValue("https://transcribestreaming.\(region).amazonaws.com", forHTTPHeaderField: "Origin")
        let task = urlSession.webSocketTask(with: request)
        webSocket = task
        isOpen = false
        pendingChunks.removeAll()
        incomingBuffer.removeAll()
        task.resume()
        listen()
    }

    func sendPcm(_ data: Data) {
        guard let webSocket else { return }
        if !isOpen {
            pendingChunks.append(data)
            return
        }
        let frameBytes = max(3200, negotiatedSampleRate / 10 * MemoryLayout<Int16>.size)
        var offset = 0
        while offset < data.count {
            let end = min(offset + frameBytes, data.count)
            let slice = data.subdata(in: offset..<end)
            let headers: [String: EventStreamHeaderValue] = [
                ":message-type": .string("event"),
                ":event-type": .string("AudioEvent"),
                ":content-type": .string("application/octet-stream")
            ]
            let frame = AWSEventStreamCodec.encode(headers: headers, payload: slice)
            webSocket.send(.data(frame)) { error in
                if let error { print("ws send error: \(error)") }
            }
            offset = end
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
        incomingBuffer.removeAll()
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
                case .data(let d):
                    self.incomingBuffer.append(d)
                    let messages = AWSEventStreamCodec.decodeAvailable(from: &self.incomingBuffer)
                    self.handleEventMessages(messages)
                case .string(let s):
                    print("ws text: \(s)")
                @unknown default:
                    break
                }
            }
            self.listen()
        }
    }

    private func handleEventMessages(_ messages: [EventStreamMessage]) {
        for msg in messages {
            if case let .string(messageType)? = msg.headers[":message-type"], messageType == "event",
               case let .string(eventType)? = msg.headers[":event-type"], eventType == "TranscriptEvent" {
                if let jsonString = String(data: msg.payload, encoding: .utf8), let jsonData = jsonString.data(using: .utf8) {
                    let decoder = JSONDecoder()
                    if let env = try? decoder.decode(AWSTranscriptEnvelope.self, from: jsonData), let tr = env.Transcript {
                        for result in tr.Results where result.IsPartial == false {
                            if let alt = result.Alternatives.first, !alt.Transcript.isEmpty {
                                if !accumulatedText.isEmpty { accumulatedText += " " }
                                accumulatedText += alt.Transcript
                            }
                        }
                    } else {
                        print("ws transcript json parse error: \(jsonString)")
                    }
                }
            } else if case let .string(mt)? = msg.headers[":message-type"], mt == "exception" {
                if let s = String(data: msg.payload, encoding: .utf8) { print("ws exception: \(s)") }
            }
        }
    }
}

extension TranscribeStreamer: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol `protocol`: String?) {
        print("WebSocket opened, protocol=\(`protocol` ?? "nil")")
        isOpen = true
        let samples = negotiatedSampleRate / 10
        let silence = Data(count: samples * MemoryLayout<Int16>.size)
        sendPcm(silence)
        while !pendingChunks.isEmpty {
            let chunk = pendingChunks.removeFirst()
            sendPcm(chunk)
        }
        webSocketTask.sendPing { _ in }
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
