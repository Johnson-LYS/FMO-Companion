import Testing
@testable import FMOc

struct APRSISPasscodeTests {
    @Test(arguments: [
        ("N0CALL", UInt16(13_023)),
        ("ZZ0TST", UInt16(19_128)),
        ("BG5ESN", UInt16(22_446)),
        ("bg5esn-10", UInt16(22_446)),
    ])
    func calculatesPublishedAlgorithmVectors(callsign: String, expected: UInt16) throws {
        #expect(try APRSISPasscode().calculate(for: callsign) == expected)
    }

    @Test(arguments: ["", "A", "BG5ESN!", "ABCDEFGHIJ"])
    func rejectsInvalidCallsigns(callsign: String) {
        #expect(throws: APRSISPasscodeError.invalidCallsign) {
            try APRSISPasscode().calculate(for: callsign)
        }
    }
}
