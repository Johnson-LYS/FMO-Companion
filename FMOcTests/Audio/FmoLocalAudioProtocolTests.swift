import Foundation
import Testing
@testable import FMOc

struct FmoLocalAudioProtocolTests {
    @Test
    func decodesFixedLittleEndianSignedPCMFrame() throws {
        var data = Data(count: FmoPCMFrame.byteCount)
        data[0] = 0x00
        data[1] = 0x80
        data[2] = 0x00
        data[3] = 0x00
        data[4] = 0xFF
        data[5] = 0x7F

        let frame = try FmoLocalAudioProtocol().decodePCM(data)

        #expect(frame.samples.count == 2_240)
        #expect(frame.samples[0] == .min)
        #expect(frame.samples[1] == 0)
        #expect(frame.samples[2] == .max)
        #expect(FmoPCMFrame.duration == 0.28)
    }

    @Test
    func rejectsEveryNonProtocolFrameLength() {
        for byteCount in [0, 4_478, 4_481, 8_960] {
            #expect(throws: FmoLocalAudioError.invalidFrameLength(byteCount)) {
                try FmoLocalAudioProtocol().decodePCM(Data(count: byteCount))
            }
        }
    }

    @Test
    func advancesOscilloscopeThroughSamplesUsingTheAudioClock() throws {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let frame = try FmoPCMFrame(
            samples: (0..<FmoPCMFrame.sampleCount).map { Int16($0) }
        )
        var buffer = FmoOscilloscopeBuffer()
        buffer.append(frame, receivedAt: start)
        let codec = FmoLocalAudioProtocol()

        let initial = codec.oscilloscopeWaveform(from: buffer, at: start)
        let advanced = codec.oscilloscopeWaveform(
            from: buffer,
            at: start.addingTimeInterval(0.1)
        )

        #expect(initial.count == 128)
        #expect(advanced.count == 128)
        #expect(advanced[0] > initial[0])
    }

    @Test
    func crossesPacketBoundaryWithoutMorphingUnrelatedSamples() throws {
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        let previousFrame = try FmoPCMFrame(
            samples: Array(repeating: 1_000, count: FmoPCMFrame.sampleCount)
        )
        let currentFrame = try FmoPCMFrame(
            samples: Array(repeating: -2_000, count: FmoPCMFrame.sampleCount)
        )
        var buffer = FmoOscilloscopeBuffer()
        buffer.append(previousFrame, receivedAt: start.addingTimeInterval(-FmoPCMFrame.duration))
        buffer.append(currentFrame, receivedAt: start)
        let codec = FmoLocalAudioProtocol()

        let boundary = codec.oscilloscopeWaveform(from: buffer, at: start)
        let current = codec.oscilloscopeWaveform(
            from: buffer,
            at: start.addingTimeInterval(FmoPCMFrame.duration)
        )

        #expect(boundary.allSatisfy { $0 > 0 })
        #expect(current.allSatisfy { $0 < 0 })
    }

    @Test
    func fadesStaleWaveformSmoothlyToBaseline() {
        let codec = FmoLocalAudioProtocol()
        let fadeStart = FmoPCMFrame.duration
            + FmoLocalAudioProtocol.waveformIdleGraceDuration

        #expect(codec.waveformIdleGain(elapsedSinceFrame: fadeStart) == 1)
        #expect(codec.waveformIdleGain(
            elapsedSinceFrame: fadeStart + FmoLocalAudioProtocol.waveformFadeDuration / 2
        ) == 0.5)
        #expect(codec.waveformIdleGain(
            elapsedSinceFrame: fadeStart + FmoLocalAudioProtocol.waveformFadeDuration
        ) == 0)
    }

    @Test
    func amplifiesWaveformForLegibilityWithoutExceedingBounds() throws {
        let start = Date(timeIntervalSinceReferenceDate: 3_000)
        let frame = try FmoPCMFrame(
            samples: Array(repeating: 20_000, count: FmoPCMFrame.sampleCount)
        )
        var buffer = FmoOscilloscopeBuffer()
        buffer.append(frame, receivedAt: start)

        let waveform = FmoLocalAudioProtocol().oscilloscopeWaveform(
            from: buffer,
            at: start
        )

        #expect(waveform.allSatisfy { $0 == 1 })
    }
}
