import AVFoundation
import Foundation
import Observation

@MainActor
protocol FmoAudioPlaying: AnyObject {
    func play(_ frame: FmoPCMFrame) throws
    func stop()
}

@MainActor
final class AVFoundationFmoAudioPlayer: FmoAudioPlaying {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var isPrepared = false
    private var scheduledBufferCount = 0
    private let maximumScheduledBufferCount = 3

    init() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: FmoPCMFrame.sampleRate,
            channels: AVAudioChannelCount(FmoPCMFrame.channelCount),
            interleaved: false
        ) else {
            preconditionFailure("Invalid fixed FMO PCM format")
        }
        self.format = format
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    func play(_ frame: FmoPCMFrame) throws {
        guard scheduledBufferCount < maximumScheduledBufferCount else { return }
        try prepareIfNeeded()
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frame.samples.count)
        ), let channel = buffer.int16ChannelData?.pointee else {
            throw FmoLocalAudioError.unsupportedMessage
        }
        buffer.frameLength = AVAudioFrameCount(frame.samples.count)
        frame.samples.withUnsafeBufferPointer { samples in
            guard let source = samples.baseAddress else { return }
            channel.update(from: source, count: samples.count)
        }

        scheduledBufferCount += 1
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.scheduledBufferCount = max(0, self.scheduledBufferCount - 1)
            }
        }
        if !playerNode.isPlaying { playerNode.play() }
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        scheduledBufferCount = 0
        isPrepared = false
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func prepareIfNeeded() throws {
        guard !isPrepared else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        engine.prepare()
        try engine.start()
        isPrepared = true
    }
}

@MainActor
@Observable
final class FmoAudioMonitorModel {
    private let client: any FmoLocalAudioStreaming
    private let player: any FmoAudioPlaying
    private var monitoringID = UUID()

    private(set) var oscilloscopeBuffer = FmoOscilloscopeBuffer()
    private(set) var isReceiving = false
    private(set) var hasProtocolError = false
    private(set) var endpointID: String?
    var isSoundEnabled = false

    init(
        client: any FmoLocalAudioStreaming,
        player: any FmoAudioPlaying = AVFoundationFmoAudioPlayer()
    ) {
        self.client = client
        self.player = player
    }

    func monitor(endpoint: FmoDeviceEndpoint) async {
        await stop(resetWaveform: false)
        let id = UUID()
        monitoringID = id
        endpointID = endpoint.id
        hasProtocolError = false

        let stream = await client.frames(from: endpoint)
        do {
            for try await frame in stream {
                try Task.checkCancellation()
                isReceiving = true
                oscilloscopeBuffer.append(frame)
                if isSoundEnabled {
                    do {
                        try player.play(frame)
                    } catch {
                        setSoundEnabled(false)
                    }
                }
            }
        } catch is CancellationError {
        } catch {
            hasProtocolError = error is FmoLocalAudioError
        }

        guard monitoringID == id, endpointID == endpoint.id else { return }
        isReceiving = false
        isSoundEnabled = false
        player.stop()
        await client.disconnect()
    }

    func setSoundEnabled(_ enabled: Bool) {
        isSoundEnabled = enabled
        if !enabled { player.stop() }
    }

    func stop(resetWaveform: Bool = false) async {
        monitoringID = UUID()
        endpointID = nil
        isReceiving = false
        isSoundEnabled = false
        player.stop()
        await client.disconnect()
        if resetWaveform {
            oscilloscopeBuffer.reset()
        }
    }
}
