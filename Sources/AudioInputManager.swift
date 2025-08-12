import AVFoundation

final class AudioInputManager {
    private let audioEngine = AVAudioEngine()
    private let inputBus: AVAudioNodeBus = 0
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    func peekSampleRate() -> Int {
        let input = audioEngine.inputNode
        let inputFormat = input.outputFormat(forBus: inputBus)
        return Int(inputFormat.sampleRate.rounded())
    }

    func startStreaming(onPcmChunk: @escaping (Data) -> Void) {
        let input = audioEngine.inputNode
        let inputFormat = input.outputFormat(forBus: inputBus)
        // Target: Int16, same sample rate as input, mono, non-interleaved
        let channelCount: AVAudioChannelCount = 1
        targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                     sampleRate: inputFormat.sampleRate,
                                     channels: channelCount,
                                     interleaved: false)
        guard let targetFormat else { return }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.removeTap(onBus: inputBus)
        input.installTap(onBus: inputBus, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter, let targetFormat = self.targetFormat else { return }

            var sourceBuffer: AVAudioPCMBuffer? = buffer
            var finished = false
            while !finished {
                let frameCapacity = AVAudioFrameCount(4096)
                guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { break }
                var error: NSError?
                let status = converter.convert(to: outBuffer, error: &error) { inNumPackets, outStatus in
                    if let sb = sourceBuffer, sb.frameLength > 0 {
                        outStatus.pointee = .haveData
                        let tmp = sourceBuffer
                        sourceBuffer = nil // consume once
                        return tmp
                    } else {
                        outStatus.pointee = .endOfStream
                        finished = true
                        return nil
                    }
                }
                if status == .error || error != nil { break }
                let frames = Int(outBuffer.frameLength)
                if frames > 0, let channel = outBuffer.int16ChannelData?.pointee {
                    let data = Data(bytes: channel, count: frames * MemoryLayout<Int16>.size)
                    onPcmChunk(data)
                }
            }
        }

        audioEngine.prepare()
        do { try audioEngine.start() } catch {
            print("Audio engine start error: \(error)")
        }
    }

    func stop() {
        audioEngine.inputNode.removeTap(onBus: inputBus)
        audioEngine.stop()
    }
}
