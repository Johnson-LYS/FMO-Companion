import Foundation

nonisolated enum APRSISPasscodeError: Error, Equatable, Sendable {
    case invalidCallsign
}

nonisolated struct APRSISPasscode: Sendable {
    func calculate(for callsign: String) throws -> UInt16 {
        let baseCallsign = callsign
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .uppercased()

        guard
            (3 ... 9).contains(baseCallsign.utf8.count),
            baseCallsign.utf8.allSatisfy(Self.isASCIIAlphanumeric)
        else {
            throw APRSISPasscodeError.invalidCallsign
        }

        var hash: UInt16 = 0x73E2
        let bytes = Array(baseCallsign.utf8)
        var index = 0
        while index < bytes.count {
            hash ^= UInt16(bytes[index]) << 8
            if index + 1 < bytes.count {
                hash ^= UInt16(bytes[index + 1])
            }
            index += 2
        }

        return hash & 0x7FFF
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (48 ... 57).contains(byte) || (65 ... 90).contains(byte)
    }
}
