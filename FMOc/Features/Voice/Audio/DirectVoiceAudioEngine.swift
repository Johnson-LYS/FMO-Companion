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

nonisolated private final class DirectVoiceCapturePipeline: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let sampleRateRatio: Double
    private let continuation: AsyncStream<[Int16]>.Continuation

    init(
        converter: AVAudioConverter,
        inputFormat: AVAudioFormat,
        outputFormat: AVAudioFormat,
        continuation: AsyncStream<[Int16]>.Continuation
    ) {
        self.converter = converter
        self.outputFormat = outputFormat
        sampleRateRatio = outputFormat.sampleRate / inputFormat.sampleRate
        self.continuation = continuation
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * sampleRateRatio)) + 8
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
              let pointer = converted.int16ChannelData?.pointee,
              converted.frameLength > 0 else { return }
        continuation.yield(Array(UnsafeBufferPointer(start: pointer, count: Int(converted.frameLength))))
    }
}

nonisolated struct DirectVoicePlaybackBacklog: Equatable, Sendable {
    static let maximumFrames = 10

    private(set) var scheduledFrames = 0
    private(set) var generation: UInt = 0

    mutating func reserveNewestFrame() -> (generation: UInt, discardedBacklog: Bool) {
        if scheduledFrames >= Self.maximumFrames {
            reset()
            scheduledFrames = 1
            return (generation, true)
        }
        scheduledFrames += 1
        return (generation, false)
    }

    mutating func completeFrame(generation: UInt) {
        guard generation == self.generation else { return }
        scheduledFrames = max(0, scheduledFrames - 1)
    }

    mutating func reset() {
        generation &+= 1
        scheduledFrames = 0
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
    private let voiceFormat: AVAudioFormat
    private var captureContinuation: AsyncStream<[Int16]>.Continuation?
    private var capturePipeline: DirectVoiceCapturePipeline?
    private var isCaptureTapInstalled = false
    private var isAudioSessionConfigured = false
    private var playbackBacklog = DirectVoicePlaybackBacklog()

    init() {
        guard let voiceFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 8_000,
            channels: 1,
            interleaved: false
        ) else {
            preconditionFailure("Invalid Direct Voice PCM format")
        }
        self.voiceFormat = voiceFormat
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: voiceFormat)
    }

    func startCapture() throws -> AsyncStream<[Int16]> {
        stopPlayback()
        stopCapture()
        try configureAudioSessionIfNeeded()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0,
              inputFormat.sampleRate > 0,
              let converter = AVAudioConverter(from: inputFormat, to: voiceFormat) else {
            throw DirectVoiceAudioError.invalidFormat
        }

        let stream = AsyncStream<[Int16]>(bufferingPolicy: .bufferingNewest(12)) { continuation in
            captureContinuation = continuation
        }
        guard let captureContinuation else {
            throw DirectVoiceAudioError.microphoneUnavailable
        }
        let pipeline = DirectVoiceCapturePipeline(
            converter: converter,
            inputFormat: inputFormat,
            outputFormat: voiceFormat,
            continuation: captureContinuation
        )
        capturePipeline = pipeline
        input.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(inputFormat.sampleRate * 0.04),
            format: inputFormat,
            block: Self.makeCaptureTapBlock(pipeline: pipeline)
        )
        isCaptureTapInstalled = true
        do {
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
        } catch {
            stopCapture()
            throw error
        }
        return stream
    }

    func stopCapture() {
        if isCaptureTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isCaptureTapInstalled = false
        }
        captureContinuation?.finish()
        captureContinuation = nil
        capturePipeline = nil
        if !player.isPlaying { engine.stop() }
    }

    func startPlaybackIfNeeded() throws {
        try configureAudioSessionIfNeeded()
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        if !player.isPlaying { player.play() }
    }

    func play(_ samples: [Int16]) throws {
        guard !samples.isEmpty else { return }
        try startPlaybackIfNeeded()
        let reservation = playbackBacklog.reserveNewestFrame()
        if reservation.discardedBacklog {
            player.stop()
            player.play()
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: voiceFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let destination = buffer.int16ChannelData?.pointee else {
            playbackBacklog.completeFrame(generation: reservation.generation)
            throw DirectVoiceAudioError.invalidFormat
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        destination.update(from: samples, count: samples.count)
        player.scheduleBuffer(
            buffer,
            completionCallbackType: .dataPlayedBack,
            completionHandler: Self.makePlaybackCompletion(
                engine: self,
                generation: reservation.generation
            )
        )
    }

    func stopPlayback() {
        player.stop()
        playbackBacklog.reset()
        if captureContinuation == nil { engine.stop() }
    }

    func stopAll() {
        stopCapture()
        stopPlayback()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isAudioSessionConfigured = false
    }

    private func configureAudioSessionIfNeeded() throws {
        guard !isAudioSessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try? session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
        isAudioSessionConfigured = true
    }

    nonisolated private static func makeCaptureTapBlock(
        pipeline: DirectVoiceCapturePipeline
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            pipeline.process(buffer)
        }
    }

    nonisolated private static func makePlaybackCompletion(
        engine: DirectVoiceAudioEngine,
        generation: UInt
    ) -> @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void {
        { [weak engine] _ in
            Task { @MainActor [weak engine] in
                engine?.playbackBacklog.completeFrame(generation: generation)
            }
        }
    }
}
