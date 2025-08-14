import Foundation
import AWSTranscribeStreaming
import AWSClientRuntime

final class TranscribeSDKStreamer {
    typealias AudioStream = TranscribeStreamingClientTypes.AudioStream

    private var client: TranscribeStreamingClient?
    private var sendContinuation: AsyncThrowingStream<AudioStream, Error>.Continuation?
    private var streamTask: Task<Void, Never>?
    private var aggregatedText: String = ""
    private var lastPartial: String = ""
    private var loggedFirstChunk: Bool = false

    func start(languageCode: String, sampleRate: Int) {
        let region = PreferencesManager.shared.region
        print("Transcribe: start region=\(region) language=\(languageCode) rate=\(sampleRate)")

        // Use default credentials resolver (no static creds)
        guard let cfg = try? TranscribeStreamingClient.TranscribeStreamingClientConfiguration(region: region) else {
            print("Transcribe: failed to create client configuration")
            return
        }
        let client = TranscribeStreamingClient(config: cfg)
        self.client = client
        print("Transcribe: client created")

        let stream = AsyncThrowingStream<AudioStream, Error> { continuation in
            self.sendContinuation = continuation
            print("Transcribe: request stream ready")
        }

        aggregatedText = ""
        lastPartial = ""

        let langEnum = TranscribeStreamingClientTypes.LanguageCode(rawValue: languageCode) ?? .enUs
        let input = StartStreamTranscriptionInput(
            audioStream: stream,
            languageCode: langEnum,
            mediaEncoding: .pcm,
            mediaSampleRateHertz: sampleRate
        )

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                print("Transcribe: starting remote stream")
                let response = try await client.startStreamTranscription(input: input)
                print("Transcribe: stream started (response received)")
                if let eventStream = response.transcriptResultStream {
                    print("Transcribe: event stream available")
                    for try await event in eventStream {
                    switch event {
                    case .transcriptevent(let te):
                        if let results = te.transcript?.results {
                                for r in results {
                                    if let alt = r.alternatives?.first, let t = alt.transcript, !t.isEmpty {
                                        if r.isPartial {
                                            self.lastPartial = t
                                            print("Transcribe: partial received")
                                        } else {
                                            if !self.aggregatedText.isEmpty { self.aggregatedText += " " }
                                            self.aggregatedText += t
                                            print("Transcribe: final segment appended")
                                        }
                                    }
                                }
                        }
                    default:
                        break
                    }
                }
                } else {
                    print("Transcribe: event stream was nil")
                }
            } catch {
                print("Transcribe stream error: \(error)")
            }
        }
    }

    func sendPcm(_ data: Data) {
        guard let continuation = sendContinuation else {
            print("Transcribe: dropping chunk before stream ready (\(data.count) bytes)")
            return
        }
        if !loggedFirstChunk {
            print("Transcribe: first chunk (\(data.count) bytes) sent")
            loggedFirstChunk = true
        }
        continuation.yield(.audioevent(TranscribeStreamingClientTypes.AudioEvent(audioChunk: data)))
    }

    func stop(completion: @escaping (String?) -> Void) {
        sendContinuation?.finish()
        sendContinuation = nil
        var text = aggregatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            text = lastPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        print("Transcribe: stop; delivering text length=\(text.count)")
        aggregatedText = ""
        lastPartial = ""
        Task { [weak self] in
            _ = await self?.streamTask?.value
            completion(text.isEmpty ? nil : text)
        }
    }
}
