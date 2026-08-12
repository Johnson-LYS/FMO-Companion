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

@MainActor
private final class AudioPlayerSpy: FmoAudioPlaying {
    private(set) var playCount = 0
    private(set) var stopCount = 0

    func play(_ frame: FmoPCMFrame) throws { playCount += 1 }
    func stop() { stopCount += 1 }
}
