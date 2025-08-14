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

    func start(languageCode: String, sampleRate: Int) {
        let region = PreferencesManager.shared.region

        // Use default credentials resolver (no static creds)
        guard let cfg = try? TranscribeStreamingClient.TranscribeStreamingClientConfiguration(region: region) else { return }
        let client = TranscribeStreamingClient(config: cfg)
        self.client = client

        let stream = AsyncThrowingStream<AudioStream, Error> { continuation in
            self.sendContinuation = continuation
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
                let response = try await client.startStreamTranscription(input: input)
                if let eventStream = response.transcriptResultStream {
                    for try await event in eventStream {
                    switch event {
                    case .transcriptevent(let te):
                        if let results = te.transcript?.results {
                                for r in results {
                                    if let alt = r.alternatives?.first, let t = alt.transcript, !t.isEmpty {
                                        if r.isPartial {
                                            self.lastPartial = t
                                        } else {
                                            if !self.aggregatedText.isEmpty { self.aggregatedText += " " }
                                            self.aggregatedText += t
                                        }
                                    }
                                }
                        }
                    default:
                        break
                    }
                }
                }
            } catch {
                print("Transcribe stream error: \(error)")
            }
        }
    }

    func sendPcm(_ data: Data) {
        sendContinuation?.yield(.audioevent(TranscribeStreamingClientTypes.AudioEvent(audioChunk: data)))
    }

    func stop(completion: @escaping (String?) -> Void) {
        sendContinuation?.finish()
        sendContinuation = nil
        var text = aggregatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            text = lastPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        aggregatedText = ""
        lastPartial = ""
        Task { [weak self] in
            _ = await self?.streamTask?.value
            completion(text.isEmpty ? nil : text)
        }
    }
}
