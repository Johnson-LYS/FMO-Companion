import Foundation

nonisolated enum FmoLocalAudioError: Error, Equatable, Sendable {
    case invalidFrameLength(Int)
    case unexpectedText
    case unsupportedMessage
}

nonisolated struct FmoPCMFrame: Equatable, Sendable {
    static let sampleRate = 8_000.0
    static let channelCount = 1
    static let bytesPerSample = 2
    static let byteCount = 4_480
    static let sampleCount = byteCount / bytesPerSample
    static let duration = Double(sampleCount) / sampleRate

    let samples: [Int16]

    init(samples: [Int16]) throws {
        guard samples.count == Self.sampleCount else {
            throw FmoLocalAudioError.invalidFrameLength(samples.count * Self.bytesPerSample)
        }
        self.samples = samples
    }
}

nonisolated struct FmoOscilloscopeBuffer: Equatable, Sendable {
    var previousSamples: [Int16] = []
    var currentSamples: [Int16] = []
    var frameStartedAt = Date.distantPast

    mutating func append(_ frame: FmoPCMFrame, receivedAt: Date = .now) {
        previousSamples = currentSamples
        currentSamples = frame.samples
        frameStartedAt = receivedAt
    }

    mutating func reset() {
        previousSamples = []
        currentSamples = []
        frameStartedAt = .distantPast
    }
}

nonisolated struct FmoLocalAudioProtocol: Sendable {
    static let waveformIdleGraceDuration = 0.04
    static let waveformFadeDuration = 0.18
    static let waveformVisualGain: Float = 2.2

    func decodePCM(_ data: Data) throws -> FmoPCMFrame {
        guard data.count == FmoPCMFrame.byteCount else {
            throw FmoLocalAudioError.invalidFrameLength(data.count)
        }

        var samples = [Int16]()
        samples.reserveCapacity(FmoPCMFrame.sampleCount)
        data.withUnsafeBytes { bytes in
            for offset in stride(from: 0, to: data.count, by: 2) {
                let value = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
                samples.append(Int16(bitPattern: value))
            }
        }
        return try FmoPCMFrame(samples: samples)
    }

    func oscilloscopeWaveform(
        from buffer: FmoOscilloscopeBuffer,
        at date: Date,
        pointCount: Int = 128,
        windowSampleCount: Int = 320
    ) -> [Float] {
        guard pointCount > 1, !buffer.currentSamples.isEmpty else {
            return Array(repeating: 0, count: max(0, pointCount))
        }

        let sampleWindowCount = max(pointCount, windowSampleCount)
        let elapsedSinceFrame = max(0, date.timeIntervalSince(buffer.frameStartedAt))
        let elapsed = min(FmoPCMFrame.duration, elapsedSinceFrame)
        let cursor = min(
            buffer.currentSamples.count,
            Int(elapsed * FmoPCMFrame.sampleRate)
        )
        let idleGain = waveformIdleGain(elapsedSinceFrame: elapsedSinceFrame)

        let windowStart: Int
        let sampleAt: (Int) -> Int16
        if buffer.previousSamples.isEmpty {
            windowStart = min(
                cursor,
                max(0, buffer.currentSamples.count - sampleWindowCount)
            )
            sampleAt = { index in
                buffer.currentSamples[min(max(0, index), buffer.currentSamples.count - 1)]
            }
        } else {
            let previousCount = buffer.previousSamples.count
            windowStart = max(0, previousCount + cursor - sampleWindowCount)
            sampleAt = { index in
                if index < previousCount {
                    return buffer.previousSamples[index]
                }
                return buffer.currentSamples[
                    min(index - previousCount, buffer.currentSamples.count - 1)
                ]
            }
        }

        let bucketSize = Double(sampleWindowCount) / Double(pointCount)
        return (0..<pointCount).map { pointIndex in
            let lower = windowStart + Int((Double(pointIndex) * bucketSize).rounded(.down))
            let upper = windowStart + Int((Double(pointIndex + 1) * bucketSize).rounded(.down))
            var peak = Int16.zero
            for sampleIndex in lower..<max(lower + 1, upper) {
                let sample = sampleAt(sampleIndex)
                if abs(Int(sample)) > abs(Int(peak)) {
                    peak = sample
                }
            }
            let normalized = Float(peak) / Float(Int16.max)
            let amplified = max(-1, min(1, normalized * Self.waveformVisualGain))
            return amplified * idleGain
        }
    }

    func waveformIdleGain(elapsedSinceFrame: TimeInterval) -> Float {
        let fadeStart = FmoPCMFrame.duration + Self.waveformIdleGraceDuration
        guard elapsedSinceFrame > fadeStart else { return 1 }

        let progress = min(
            1,
            max(0, (elapsedSinceFrame - fadeStart) / Self.waveformFadeDuration)
        )
        let easedProgress = progress * progress * (3 - 2 * progress)
        return Float(1 - easedProgress)
    }
}
