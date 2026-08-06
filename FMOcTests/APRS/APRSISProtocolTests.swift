import Foundation
import Testing
@testable import FMOc

struct APRSISProtocolTests {
    @Test
    func buildsReceiveOnlyLoginWithFixedFMOV4FilterAndCRLF() throws {
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "ZZ0TST", ssid: 10)
        let sut = try APRSISProtocol(
            softwareName: "FMOCompanion",
            softwareVersion: "0.4"
        )

        let command = sut.makeLoginCommand(for: identity)

        #expect(
            String(decoding: command, as: UTF8.self)
                == "user ZZ0TST-10 pass -1 vers FMOCompanion 0.4 filter u/APFMO4\r\n"
        )
        #expect(command.count <= 512)
    }

    @Test
    func acceptsExpectedReceiveOnlyLoginResponse() throws {
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "ZZ0TST", ssid: 10)
        let sut = try APRSISProtocol(
            softwareName: "FMOCompanion",
            softwareVersion: "0.4"
        )

        let response = try sut.parseLoginResponse(
            "# logresp ZZ0TST-10 unverified, server T2TEST\r\n",
            expectedIdentity: identity
        )

        #expect(response == APRSISLoginResponse(serverCallsign: "T2TEST"))
    }

    @Test
    func rejectsLoginResponseForAnotherIdentity() throws {
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "ZZ0TST", ssid: 10)
        let sut = try APRSISProtocol(
            softwareName: "FMOCompanion",
            softwareVersion: "0.4"
        )

        #expect(throws: APRSISProtocolError.loginIdentityMismatch) {
            try sut.parseLoginResponse(
                "# logresp ZZ0TST-11 unverified, server T2TEST",
                expectedIdentity: identity
            )
        }
    }

    @Test
    func doesNotTreatVerifiedSessionAsExpectedReceiveOnlyHandshake() throws {
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "ZZ0TST", ssid: 10)
        let sut = try APRSISProtocol(
            softwareName: "FMOCompanion",
            softwareVersion: "0.4"
        )

        #expect(throws: APRSISProtocolError.unexpectedVerificationStatus) {
            try sut.parseLoginResponse(
                "# logresp ZZ0TST-10 verified, server T2TEST",
                expectedIdentity: identity
            )
        }
    }

    @Test(arguments: [
        ("FMO Companion", "0.4"),
        ("FMOCompanion", "0.4 beta"),
    ])
    func rejectsSoftwareMetadataThatWouldBreakLoginLine(
        softwareName: String,
        softwareVersion: String
    ) {
        #expect(throws: APRSISProtocolError.self) {
            try APRSISProtocol(
                softwareName: softwareName,
                softwareVersion: softwareVersion
            )
        }
    }

    @Test
    func rejectsLoginResponseWithoutServerIdentity() throws {
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "ZZ0TST", ssid: 10)
        let sut = try APRSISProtocol(
            softwareName: "FMOCompanion",
            softwareVersion: "0.4"
        )

        #expect(throws: APRSISProtocolError.invalidLoginResponse) {
            try sut.parseLoginResponse(
                "# logresp ZZ0TST-10 unverified",
                expectedIdentity: identity
            )
        }
    }

    @Test
    func rejectsOversizedSoftwareMetadata() {
        #expect(throws: APRSISProtocolError.invalidSoftwareName) {
            try APRSISProtocol(
                softwareName: String(repeating: "A", count: 33),
                softwareVersion: "0.4"
            )
        }
    }
}
