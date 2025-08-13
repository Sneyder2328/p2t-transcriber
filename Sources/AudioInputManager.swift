import AVFoundation

final class AudioInputManager {
    private let audioEngine = AVAudioEngine()
    private let inputBus: AVAudioNodeBus = 0
    private var converter: AVAudioConverter?

    private let targetFormat: AVAudioFormat = {
        let sampleRate: Double = 16000
        let channelCount: AVAudioChannelCount = 1
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: channelCount,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        return AVAudioFormat(streamDescription: &asbd)!
    }()

    func peekSampleRate() -> Int { return 16000 }

    func startStreaming(onPcmChunk: @escaping (Data) -> Void) {
        let input = audioEngine.inputNode
        let inputFormat = input.outputFormat(forBus: inputBus)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.removeTap(onBus: inputBus)
        input.installTap(onBus: inputBus, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let converter = self.converter else { return }

            let ratio = self.targetFormat.sampleRate / inputFormat.sampleRate
            let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: frameCapacity) else { return }

            var error: NSError?
            converter.convert(to: outBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if error != nil { return }
            let frames = Int(outBuffer.frameLength)
            guard frames > 0, let channel = outBuffer.int16ChannelData?.pointee else { return }
            let data = Data(bytes: channel, count: frames * MemoryLayout<Int16>.size)
            onPcmChunk(data)
        }

        audioEngine.prepare()
        do { try audioEngine.start() } catch { print("Audio engine start error: \(error)") }
    }

    func stop() {
        audioEngine.inputNode.removeTap(onBus: inputBus)
        audioEngine.stop()
    }
}
