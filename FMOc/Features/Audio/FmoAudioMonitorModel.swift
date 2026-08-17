import AVFoundation
import Foundation
import Observation

@MainActor
protocol FmoAudioPlaying: AnyObject {
    func start() throws
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

    func start() throws {
        try prepareIfNeeded()
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    func play(_ frame: FmoPCMFrame) throws {
        guard scheduledBufferCount < maximumScheduledBufferCount else { return }
        try start()
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
    private var soundPreferenceEndpointID: String?

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
        let changesDevice = soundPreferenceEndpointID != nil && soundPreferenceEndpointID != endpoint.id
        await stop(resetWaveform: false, resetSound: changesDevice)
        soundPreferenceEndpointID = endpoint.id
        let id = UUID()
        monitoringID = id
        endpointID = endpoint.id
        hasProtocolError = false

        _ = await consumeFrames(from: endpoint, monitoringID: id)

        guard monitoringID == id, endpointID == endpoint.id else { return }
        isReceiving = false
        if !isSoundEnabled {
            player.stop()
        }
        await client.disconnect()
    }

    /// 在 App 前台且设备保持连接时持续维护音频流。
    ///
    /// FMO 的音频 WebSocket 可能在网络切换、短暂不可达或长时间无数据后结束。
    /// 这些瞬时中断不应改变用户的静音选择，因此只重建流，不重置开关。
    func monitorContinuously(
        endpoint: FmoDeviceEndpoint,
        retryDelay: Duration = .seconds(1)
    ) async {
        let changesDevice = soundPreferenceEndpointID != nil && soundPreferenceEndpointID != endpoint.id
        await stop(resetWaveform: false, resetSound: changesDevice)
        soundPreferenceEndpointID = endpoint.id
        let id = UUID()
        monitoringID = id
        endpointID = endpoint.id
        hasProtocolError = false
        if isSoundEnabled {
            do {
                try player.start()
            } catch {
                setSoundEnabled(false)
            }
        }

        while !Task.isCancelled, monitoringID == id, endpointID == endpoint.id {
            let result = await consumeFrames(from: endpoint, monitoringID: id)
            guard monitoringID == id, endpointID == endpoint.id else { return }

            isReceiving = false
            if !isSoundEnabled {
                player.stop()
            }
            await client.disconnect()

            guard monitoringID == id, endpointID == endpoint.id else { return }
            if case .cancelled = result { return }

            do {
                try await Task.sleep(for: retryDelay)
            } catch {
                return
            }
        }
    }

    func setSoundEnabled(_ enabled: Bool) {
        guard enabled else {
            isSoundEnabled = false
            player.stop()
            return
        }

        do {
            try player.start()
            isSoundEnabled = true
        } catch {
            isSoundEnabled = false
            player.stop()
        }
    }

    func stop(resetWaveform: Bool = false, resetSound: Bool = true) async {
        monitoringID = UUID()
        endpointID = nil
        isReceiving = false
        if resetSound {
            isSoundEnabled = false
            soundPreferenceEndpointID = nil
        }
        player.stop()
        await client.disconnect()
        if resetWaveform {
            oscilloscopeBuffer.reset()
        }
    }

    private enum StreamResult {
        case finished
        case cancelled
        case failed
    }

    private func consumeFrames(
        from endpoint: FmoDeviceEndpoint,
        monitoringID id: UUID
    ) async -> StreamResult {
        let stream = await client.frames(from: endpoint)
        do {
            for try await frame in stream {
                try Task.checkCancellation()
                guard monitoringID == id, endpointID == endpoint.id else {
                    return .cancelled
                }
                isReceiving = true
                hasProtocolError = false
                oscilloscopeBuffer.append(frame)
                if isSoundEnabled {
                    do {
                        try player.play(frame)
                    } catch {
                        setSoundEnabled(false)
                    }
                }
            }
            return .finished
        } catch is CancellationError {
            return .cancelled
        } catch {
            hasProtocolError = error is FmoLocalAudioError
            return .failed
        }
    }
}

nonisolated enum FmoAudioSessionEventPolicy {
    static func shouldDisableSound(forInterruption notification: Notification) -> Bool {
        guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawValue) else {
            return false
        }
        return type == .began
    }

    static func shouldDisableSound(forRouteChange notification: Notification) -> Bool {
        guard let rawValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawValue) else {
            return false
        }
        return reason == .oldDeviceUnavailable
    }
}
