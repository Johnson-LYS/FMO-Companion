import Foundation
import Testing
@testable import FMOc

struct DeterministicCBORTests {
    @Test
    func roundTripsSupportedCanonicalValues() throws {
        let value = DeterministicCBORValue.array([
            .text("FMO"),
            .unsigned(4),
            .bytes(Data([0x01, 0x02])),
            .boolean(true),
        ])

        let encoded = try DeterministicCBOR().encode(value)

        #expect(encoded == Data([0x84, 0x63, 0x46, 0x4D, 0x4F, 0x04, 0x42, 0x01, 0x02, 0xF5]))
        #expect(try DeterministicCBOR().decode(encoded) == value)
    }

    @Test
    func rejectsNonCanonicalAndTrailingData() {
        #expect(throws: DeterministicCBORError.nonCanonical) {
            try DeterministicCBOR().decode(Data([0x18, 0x01]))
        }
        #expect(throws: DeterministicCBORError.trailingBytes) {
            try DeterministicCBOR().decode(Data([0x01, 0x02]))
        }
        #expect(throws: DeterministicCBORError.unsupportedType) {
            try DeterministicCBOR().decode(Data([0x9F, 0x01, 0xFF]))
        }
    }
}
