import Foundation
import Testing
@testable import FMOc

@MainActor
struct FmoAudioMonitorModelTests {
    @Test
    func avFoundationPlayerStartsFixedPCMWithPlaybackSession() throws {
        let player = AVFoundationFmoAudioPlayer()
        let frame = try FmoPCMFrame(
            samples: Array(repeating: 0, count: FmoPCMFrame.sampleCount)
        )

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
    func enablingSoundOnlyPlaysNewFramesAndStopResetsToggle() async throws {
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
        #expect(model.isSoundEnabled == false)

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
    private(set) var playCount = 0
    private(set) var stopCount = 0

    func play(_ frame: FmoPCMFrame) throws { playCount += 1 }
    func stop() { stopCount += 1 }
}
