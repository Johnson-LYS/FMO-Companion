import Testing
@testable import FMOc

struct ReceiveOnlyAPRSIdentityTests {
    @Test
    func normalizesCallsignAndBuildsLoginCallsign() throws {
        let identity = try ReceiveOnlyAPRSIdentity(callsign: " zz0tst ", ssid: 10)

        #expect(identity.callsign == "ZZ0TST")
        #expect(identity.ssid == 10)
        #expect(identity.loginCallsign == "ZZ0TST-10")
    }

    @Test
    func omitsZeroSSIDFromLoginCallsign() throws {
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "ZZ0TST", ssid: 0)

        #expect(identity.loginCallsign == "ZZ0TST")
    }

    @Test(arguments: ["", "AB", "ZZ0-TST", "ZZ0 TST", "呼号"])
    func rejectsInvalidCallsign(_ callsign: String) {
        #expect(throws: ReceiveOnlyAPRSIdentityError.self) {
            try ReceiveOnlyAPRSIdentity(callsign: callsign, ssid: 10)
        }
    }

    @Test(arguments: [-1, 16])
    func rejectsSSIDOutsideAX25Range(_ ssid: Int) {
        #expect(throws: ReceiveOnlyAPRSIdentityError.invalidSSID) {
            try ReceiveOnlyAPRSIdentity(callsign: "ZZ0TST", ssid: ssid)
        }
    }

    @Test
    func rejectsLoginCallsignLongerThanNineBytes() {
        #expect(throws: ReceiveOnlyAPRSIdentityError.loginCallsignTooLong) {
            try ReceiveOnlyAPRSIdentity(callsign: "ZZ0TSTA", ssid: 10)
        }
    }
}
