import AVFoundation
import Foundation
import Testing
@testable import FMOc

@MainActor
struct FmoAudioMonitorModelTests {
    @Test
    func audioSessionEventsOnlyMuteForRealInterruptionOrRemovedRoute() {
        let categoryChange = Notification(
            name: AVAudioSession.routeChangeNotification,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.categoryChange.rawValue
            ]
        )
        let removedRoute = Notification(
            name: AVAudioSession.routeChangeNotification,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            ]
        )
        let interruptionEnded = Notification(
            name: AVAudioSession.interruptionNotification,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue
            ]
        )
        let interruptionBegan = Notification(
            name: AVAudioSession.interruptionNotification,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )

        #expect(!FmoAudioSessionEventPolicy.shouldDisableSound(forRouteChange: categoryChange))
        #expect(FmoAudioSessionEventPolicy.shouldDisableSound(forRouteChange: removedRoute))
        #expect(!FmoAudioSessionEventPolicy.shouldDisableSound(forInterruption: interruptionEnded))
        #expect(FmoAudioSessionEventPolicy.shouldDisableSound(forInterruption: interruptionBegan))
    }

    @Test
    func avFoundationPlayerStartsFixedPCMWithPlaybackSession() throws {
        let player = AVFoundationFmoAudioPlayer()
        let frame = try FmoPCMFrame(
            samples: Array(repeating: 0, count: FmoPCMFrame.sampleCount)
        )

        try player.start()
        try player.play(frame)
        player.stop()
    }

    @Test
    func defaultsMutedButStillUpdatesWaveform() async throws {
        let frame = try FmoPCMFrame(
            samples: (0..<FmoPCMFrame.sampleCount).map { Int16(clamping: ($0 % 40) * 500) }
        )
        let client = DelayedAudioStream(frame: frame)
        let player = AudioPlayerSpy()
        let model = FmoAudioMonitorModel(client: client, player: player)
        let endpoint = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual)

        await model.monitor(endpoint: endpoint)

        #expect(model.isSoundEnabled == false)
        #expect(model.oscilloscopeBuffer.currentSamples.contains { $0 != 0 })
        #expect(player.playCount == 0)
    }

    @Test
    func enablingSoundOnlyPlaysNewFramesAndExplicitStopResetsToggle() async throws {
        let frame = try FmoPCMFrame(samples: Array(repeating: 1_000, count: FmoPCMFrame.sampleCount))
        let client = DelayedAudioStream(frame: frame)
        let player = AudioPlayerSpy()
        let model = FmoAudioMonitorModel(client: client, player: player)
        let endpoint = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual)

        let monitoringTask = Task { await model.monitor(endpoint: endpoint) }
        try await Task.sleep(for: .milliseconds(5))
        model.setSoundEnabled(true)
        await monitoringTask.value

        #expect(player.playCount == 1)
        #expect(model.isSoundEnabled)

        await model.stop()
        #expect(model.isSoundEnabled == false)
    }

    @Test
    func transientStreamEndReconnectsWithoutResettingSoundToggle() async throws {
        let frame = try FmoPCMFrame(
            samples: Array(repeating: 1_000, count: FmoPCMFrame.sampleCount)
        )
        let client = ReconnectingAudioStream(frame: frame)
        let player = AudioPlayerSpy()
        let model = FmoAudioMonitorModel(client: client, player: player)
        let endpoint = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual)

        let monitoringTask = Task {
            await model.monitorContinuously(
                endpoint: endpoint,
                retryDelay: .milliseconds(5)
            )
        }
        while model.endpointID == nil {
            await Task.yield()
        }
        model.setSoundEnabled(true)

        for _ in 0..<50 where player.playCount == 0 {
            try await Task.sleep(for: .milliseconds(2))
        }

        let attemptCount = await client.attemptCount
        #expect(attemptCount >= 2)
        #expect(player.playCount >= 1)
        #expect(model.oscilloscopeBuffer.currentSamples.contains { $0 != 0 })
        #expect(model.isSoundEnabled)

        monitoringTask.cancel()
        await monitoringTask.value
        await model.stop()
        #expect(model.isSoundEnabled == false)
    }

    @Test
    func temporaryStopCanPreserveSoundPreferenceForAutomaticRecovery() async throws {
        let client = DelayedAudioStream(
            frame: try FmoPCMFrame(samples: Array(repeating: 0, count: FmoPCMFrame.sampleCount))
        )
        let player = AudioPlayerSpy()
        let model = FmoAudioMonitorModel(client: client, player: player)

        model.setSoundEnabled(true)
        await model.stop(resetWaveform: false, resetSound: false)

        #expect(model.isSoundEnabled)
        #expect(player.startCount == 1)
    }

    @Test
    func switchingDeviceResetsTheSoundPreference() async throws {
        let client = DelayedAudioStream(
            frame: try FmoPCMFrame(samples: Array(repeating: 0, count: FmoPCMFrame.sampleCount))
        )
        let model = FmoAudioMonitorModel(client: client, player: AudioPlayerSpy())
        let first = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual)
        let second = try FmoDeviceEndpoint(host: "192.0.2.11", source: .manual)

        await model.monitor(endpoint: first)
        model.setSoundEnabled(true)
        await model.stop(resetWaveform: false, resetSound: false)
        await model.monitor(endpoint: second)

        #expect(!model.isSoundEnabled)
    }
}

private struct DelayedAudioStream: FmoLocalAudioStreaming {
    let frame: FmoPCMFrame

    func frames(from endpoint: FmoDeviceEndpoint) async -> AsyncThrowingStream<FmoPCMFrame, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                try? await Task.sleep(for: .milliseconds(20))
                continuation.yield(frame)
                continuation.finish()
            }
        }
    }

    func disconnect() async {}
}

private actor ReconnectingAudioStream: FmoLocalAudioStreaming {
    let frame: FmoPCMFrame
    private(set) var attemptCount = 0

    init(frame: FmoPCMFrame) {
        self.frame = frame
    }

    func frames(from endpoint: FmoDeviceEndpoint) async -> AsyncThrowingStream<FmoPCMFrame, any Error> {
        attemptCount += 1
        let attempt = attemptCount
        let frame = self.frame
        return AsyncThrowingStream { continuation in
            Task {
                if attempt == 1 {
                    try? await Task.sleep(for: .milliseconds(8))
                    continuation.finish()
                    return
                }
                try? await Task.sleep(for: .milliseconds(8))
                continuation.yield(frame)
                continuation.finish()
            }
        }
    }

    func disconnect() async {}
}

@MainActor
private final class AudioPlayerSpy: FmoAudioPlaying {
    private(set) var startCount = 0
    private(set) var playCount = 0
    private(set) var stopCount = 0

    func start() throws { startCount += 1 }
    func play(_ frame: FmoPCMFrame) throws { playCount += 1 }
    func stop() { stopCount += 1 }
}
