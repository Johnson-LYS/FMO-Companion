import Foundation
import Testing
@testable import FMOc

struct FmoRemoteControlProtocolTests {
    private let codec = FmoRemoteControlCodec()

    @Test
    func calculatesMinuteTimeSlot() throws {
        #expect(try codec.timeSlot(for: Date(timeIntervalSince1970: 1_800_000_059)) == 30_000_000)
    }

    @Test
    func matchesIndependentHMACAndFrameVector() throws {
        let command = FmoRemoteCommand(
            source: TNC2Address(callsign: "BG5ESN", ssid: 10),
            target: TNC2Address(callsign: "BD7XYZ", ssid: 1),
            action: .standby,
            timeSlot: 30_000_000,
            counter: 2
        )

        #expect(try codec.signature(for: command, secret: "ABCDEF123456") == "3DFD67625F675096")
        #expect(
            try codec.encode(command, secret: "ABCDEF123456")
                == "BG5ESN-10>APFMO0,TCPIP*::BD7XYZ-1 :CONTROL,STANDBY,30000000,2,3DFD67625F675096"
        )
    }

    @Test
    func rejectsMalformedSecret() throws {
        let command = FmoRemoteCommand(
            source: TNC2Address(callsign: "BG5ESN", ssid: 10),
            target: TNC2Address(callsign: "BD7XYZ", ssid: 1),
            action: .normal,
            timeSlot: 1,
            counter: 0
        )

        #expect(throws: FmoRemoteControlError.invalidSecret) {
            try codec.encode(command, secret: "secret")
        }
    }
}
