@preconcurrency import AVFoundation
import Foundation

nonisolated private final class AudioConverterInputBox: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var wasSupplied = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard !wasSupplied else { return nil }
        wasSupplied = true
        return buffer
    }
}

nonisolated enum DirectVoiceAudioError: Error, Equatable, Sendable {
    case invalidFormat
    case conversionFailed
    case microphoneUnavailable
}

@MainActor
final class DirectVoiceAudioEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var captureContinuation: AsyncStream<[Int16]>.Continuation?
    private var isPlayerAttached = false

    func startCapture() throws -> AsyncStream<[Int16]> {
        stopCapture()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0,
              let outputFormat = AVAudioFormat(
                  commonFormat: .pcmFormatInt16,
                  sampleRate: 8_000,
                  channels: 1,
                  interleaved: true
              ),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw DirectVoiceAudioError.invalidFormat
        }

        let stream = AsyncStream<[Int16]>(bufferingPolicy: .bufferingNewest(12)) { continuation in
            captureContinuation = continuation
        }
        let continuation = captureContinuation
        input.installTap(onBus: 0, bufferSize: 1_920, format: inputFormat) { buffer, _ in
            let capacity = AVAudioFrameCount(
                ceil(Double(buffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate)
            ) + 8
            guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
            let inputBox = AudioConverterInputBox(buffer: buffer)
            var conversionError: NSError?
            let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
                guard let inputBuffer = inputBox.take() else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                inputStatus.pointee = .haveData
                return inputBuffer
            }
            guard status != .error, conversionError == nil,
                  let pointer = converted.int16ChannelData?[0], converted.frameLength > 0 else { return }
            continuation?.yield(Array(UnsafeBufferPointer(start: pointer, count: Int(converted.frameLength))))
        }
        engine.prepare()
        try engine.start()
        return stream
    }

    func stopCapture() {
        engine.inputNode.removeTap(onBus: 0)
        captureContinuation?.finish()
        captureContinuation = nil
        if !player.isPlaying { engine.stop() }
    }

    func startPlaybackIfNeeded() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true)
        if !isPlayerAttached {
            engine.attach(player)
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 8_000,
                channels: 1,
                interleaved: true
            ) else { throw DirectVoiceAudioError.invalidFormat }
            engine.connect(player, to: engine.mainMixerNode, format: format)
            isPlayerAttached = true
        }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        if !player.isPlaying { player.play() }
    }

    func play(_ samples: [Int16]) throws {
        guard !samples.isEmpty else { return }
        try startPlaybackIfNeeded()
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 8_000,
            channels: 1,
            interleaved: true
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
        let destination = buffer.int16ChannelData?[0] else {
            throw DirectVoiceAudioError.invalidFormat
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        destination.update(from: samples, count: samples.count)
        player.scheduleBuffer(buffer)
    }

    func stopPlayback() {
        player.stop()
        if captureContinuation == nil { engine.stop() }
    }

    func stopAll() {
        stopCapture()
        stopPlayback()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
