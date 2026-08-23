import Foundation
import Testing
@testable import FMOc

struct FMORawProtocolTests {
    @Test func encoderAndParserRoundTrip() throws {
        let encoded = try FMORawEncoder().encode(
            uid: 1_000_000_001,
            callsign: "bi8syn",
            streamBeginUTC: 0xFFFF_FF00,
            timestamp: 123,
            serverUID: 5001,
            frames: [Data([1, 2, 3]), Data([4, 5])]
        )
        let packet = try FMORawParser().parse(encoded)
        #expect(packet.header.vendor == 0x2000)
        #expect(packet.header.callsign == "BI8SYN")
        #expect(packet.header.frameCount == 2)
        #expect(packet.frames.map(\.payload) == [Data([1, 2, 3]), Data([4, 5])])
    }

    @Test func parserRejectsChecksumMismatch() throws {
        var encoded = try FMORawEncoder().encode(
            uid: 42,
            callsign: "BI8SYN",
            streamBeginUTC: 1,
            timestamp: 2,
            serverUID: 3,
            frames: [Data([9, 8, 7])]
        )
        encoded[encoded.count - 1] ^= 0xFF
        #expect(throws: FMORawError.checksumMismatch) {
            try FMORawParser().parse(encoded)
        }
    }

    @Test func crcMatchesKnownVector() {
        #expect(FMOCRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    }
}

struct FMOVoiceRouteArbiterTests {
    @Test func sameUIDContinuesAndSmallerUIDWinsTie() {
        var arbiter = FMOVoiceRouteArbiter()
        #expect(arbiter.consider(uid: 20, streamBeginUTC: 100, nowMilliseconds: 1_000) == .accepted)
        #expect(arbiter.consider(uid: 20, streamBeginUTC: 100, nowMilliseconds: 1_200) == .continued)
        #expect(arbiter.consider(uid: 10, streamBeginUTC: 100, nowMilliseconds: 1_300) == .preempted(previousUID: 20))
    }

    @Test func expiredRouteAcceptsNewStream() {
        var arbiter = FMOVoiceRouteArbiter()
        _ = arbiter.consider(uid: 20, streamBeginUTC: 500, nowMilliseconds: 100)
        #expect(arbiter.consider(uid: 30, streamBeginUTC: 900, nowMilliseconds: 1_601) == .preempted(previousUID: 20))
    }

    @Test func earlierStreamUsesWrappingComparison() {
        var arbiter = FMOVoiceRouteArbiter()
        _ = arbiter.consider(uid: 20, streamBeginUTC: 100, nowMilliseconds: 100)
        #expect(arbiter.consider(uid: 30, streamBeginUTC: UInt32.max - 899, nowMilliseconds: 200) == .preempted(previousUID: 20))
    }
}
