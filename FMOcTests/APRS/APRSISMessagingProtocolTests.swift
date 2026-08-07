import Foundation
import Testing
@testable import FMOc

struct APRSISMessagingProtocolTests {
    @Test
    func buildsVerifiedLoginWithoutPersistedPasscode() throws {
        let protocolCodec = try APRSISMessagingProtocol(
            softwareName: "FMOCompanion",
            softwareVersion: "0.6"
        )
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "BG5ESN", ssid: 10)

        #expect(
            String(decoding: try protocolCodec.makeLoginCommand(for: identity), as: UTF8.self)
                == "user BG5ESN-10 pass 22446 vers FMOCompanion 0.6 filter g/BG5ESN-10\r\n"
        )
    }

    @Test
    func acceptsOnlyVerifiedResponseForExpectedIdentity() throws {
        let protocolCodec = try APRSISMessagingProtocol(
            softwareName: "FMOCompanion",
            softwareVersion: "0.6"
        )
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "BG5ESN", ssid: 10)

        #expect(
            try protocolCodec.parseLoginResponse(
                "# logresp BG5ESN-10 verified, server T2TEST",
                expectedIdentity: identity
            ) == APRSISLoginResponse(serverCallsign: "T2TEST")
        )
        #expect(throws: APRSISMessagingProtocolError.loginRejected) {
            try protocolCodec.parseLoginResponse(
                "# logresp BG5ESN-10 unverified, server T2TEST",
                expectedIdentity: identity
            )
        }
    }

    @Test
    func rejectsLineInjection() throws {
        let protocolCodec = try APRSISMessagingProtocol(
            softwareName: "FMOCompanion",
            softwareVersion: "0.6"
        )
        #expect(throws: APRSISMessagingProtocolError.invalidPacket) {
            try protocolCodec.makePacketCommand("FRAME\r\nINJECTED")
        }
        #expect(throws: APRSISMessagingProtocolError.invalidPacket) {
            try protocolCodec.makePacketCommand("FRAME\rINJECTED")
        }
        #expect(throws: APRSISMessagingProtocolError.invalidPacket) {
            try protocolCodec.makePacketCommand("FRAME\nINJECTED")
        }
    }
}
