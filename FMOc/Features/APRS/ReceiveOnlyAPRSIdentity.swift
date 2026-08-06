import Foundation

nonisolated enum ReceiveOnlyAPRSIdentityError: Error, Equatable, Sendable {
    case emptyCallsign
    case invalidCallsign
    case invalidSSID
    case loginCallsignTooLong
}

nonisolated struct ReceiveOnlyAPRSIdentity: Equatable, Hashable, Sendable {
    let callsign: String
    let ssid: UInt8

    init(callsign: String, ssid: Int) throws {
        let normalizedCallsign = callsign
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !normalizedCallsign.isEmpty else {
            throw ReceiveOnlyAPRSIdentityError.emptyCallsign
        }

        guard
            normalizedCallsign.utf8.count >= 3,
            normalizedCallsign.utf8.allSatisfy(Self.isASCIIAlphanumeric)
        else {
            throw ReceiveOnlyAPRSIdentityError.invalidCallsign
        }

        guard (0 ... 15).contains(ssid) else {
            throw ReceiveOnlyAPRSIdentityError.invalidSSID
        }

        let normalizedSSID = UInt8(ssid)
        let loginCallsign = Self.makeLoginCallsign(
            callsign: normalizedCallsign,
            ssid: normalizedSSID
        )
        guard loginCallsign.utf8.count <= 9 else {
            throw ReceiveOnlyAPRSIdentityError.loginCallsignTooLong
        }

        self.callsign = normalizedCallsign
        self.ssid = normalizedSSID
    }

    var loginCallsign: String {
        Self.makeLoginCallsign(callsign: callsign, ssid: ssid)
    }

    private static func makeLoginCallsign(callsign: String, ssid: UInt8) -> String {
        ssid == 0 ? callsign : "\(callsign)-\(ssid)"
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (48 ... 57).contains(byte) || (65 ... 90).contains(byte)
    }
}
