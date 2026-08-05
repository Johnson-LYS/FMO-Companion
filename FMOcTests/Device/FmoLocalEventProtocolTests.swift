import Foundation
import Testing
@testable import FMOc

struct FmoLocalEventProtocolTests {
    private let codec = FmoLocalEventProtocol()

    @Test
    func decodesSpeakingAndIdleStatesWithoutTreatingIdleAsACallsign() throws {
        let speaking = Data(#"{"type":"qso","subType":"callsign","data":{"callsign":"BG1ABC","grid":"OM20xx","isHost":false,"isSpeaking":true},"level":"info","seq":7,"src":"qso","ts":12345}"#.utf8)
        let idle = Data(#"{"type":"qso","subType":"callsign","data":{"callsign":"","grid":"","isHost":false,"isSpeaking":false},"level":"info","seq":8,"src":"qso","ts":12500}"#.utf8)

        #expect(
            try codec.decodeEvent(speaking) == .speaking(
                FmoSpeakingState(
                    callsign: "BG1ABC",
                    grid: "OM20xx",
                    isSpeaking: true,
                    sequence: 7,
                    deviceUptimeMilliseconds: 12_345
                )
            )
        )
        #expect(
            try codec.decodeEvent(idle) == .speaking(
                FmoSpeakingState(
                    callsign: nil,
                    grid: nil,
                    isSpeaking: false,
                    sequence: 8,
                    deviceUptimeMilliseconds: 12_500
                )
            )
        )
    }

    @Test
    func decodesAtMostTwentyRecentActivitiesFromUtcSeconds() throws {
        let fixture = Data(#"{"type":"qso","subType":"history","data":[{"callsign":"BG1ABC","utcTime":1700000000},{"callsign":"BG2XYZ","utcTime":1699999900}],"level":"info","seq":9,"src":"qso","ts":12600}"#.utf8)

        let event = try codec.decodeEvent(fixture)
        #expect(
            event == .history([
                FmoRecentLocalActivity(callsign: "BG1ABC", occurredAt: Date(timeIntervalSince1970: 1_700_000_000)),
                FmoRecentLocalActivity(callsign: "BG2XYZ", occurredAt: Date(timeIntervalSince1970: 1_699_999_900))
            ])
        )
    }

    @Test
    func acceptsSpeakingEventWithoutOptionalGrid() throws {
        let fixture = Data(#"{"type":"qso","subType":"callsign","data":{"callsign":"BG1ABC","isSpeaking":true},"seq":10,"ts":13000}"#.utf8)

        #expect(
            try codec.decodeEvent(fixture) == .speaking(
                FmoSpeakingState(
                    callsign: "BG1ABC",
                    grid: nil,
                    isSpeaking: true,
                    sequence: 10,
                    deviceUptimeMilliseconds: 13_000
                )
            )
        )
    }

    @Test
    func ignoresUnrelatedEventsAndRejectsSpeakingWithoutCallsign() throws {
        let unrelated = Data(#"{"type":"system","subType":"heartbeat","data":{}}"#.utf8)
        let invalid = Data(#"{"type":"qso","subType":"callsign","data":{"callsign":"","grid":"","isSpeaking":true},"seq":1,"ts":2}"#.utf8)

        #expect(try codec.decodeEvent(unrelated) == nil)
        #expect(throws: FmoDeviceError.protocolViolation) {
            try codec.decodeEvent(invalid)
        }
    }
}
