import Foundation

nonisolated enum APRSISMessagingProtocolError: Error, Equatable, Sendable {
    case invalidSoftwareMetadata
    case invalidLoginResponse
    case loginIdentityMismatch
    case loginRejected
    case invalidPacket
}

nonisolated struct APRSISMessagingProtocol: Sendable {
    private let softwareName: String
    private let softwareVersion: String
    private let passcodeCalculator: APRSISPasscode

    init(
        softwareName: String,
        softwareVersion: String,
        passcodeCalculator: APRSISPasscode = APRSISPasscode()
    ) throws {
        guard
            Self.isValidSoftwareToken(softwareName),
            Self.isValidSoftwareToken(softwareVersion)
        else {
            throw APRSISMessagingProtocolError.invalidSoftwareMetadata
        }
        self.softwareName = softwareName
        self.softwareVersion = softwareVersion
        self.passcodeCalculator = passcodeCalculator
    }

    func makeLoginCommand(for identity: ReceiveOnlyAPRSIdentity) throws -> Data {
        let passcode = try passcodeCalculator.calculate(for: identity.callsign)
        let line = [
            "user", identity.loginCallsign,
            "pass", String(passcode),
            "vers", softwareName, softwareVersion,
            "filter", "g/\(identity.loginCallsign)",
        ].joined(separator: " ")
        return Data("\(line)\r\n".utf8)
    }

    func parseLoginResponse(
        _ line: String,
        expectedIdentity: ReceiveOnlyAPRSIdentity
    ) throws -> APRSISLoginResponse {
        let components = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard
            components.count >= 4,
            components[0] == "#",
            components[1].lowercased() == "logresp"
        else {
            throw APRSISMessagingProtocolError.invalidLoginResponse
        }
        guard components[2].uppercased() == expectedIdentity.loginCallsign else {
            throw APRSISMessagingProtocolError.loginIdentityMismatch
        }
        let status = components[3]
            .trimmingCharacters(in: CharacterSet(charactersIn: ","))
            .lowercased()
        guard status == "verified" else {
            throw APRSISMessagingProtocolError.loginRejected
        }
        guard
            let serverIndex = components.firstIndex(where: { $0.lowercased() == "server" }),
            components.indices.contains(serverIndex + 1)
        else {
            throw APRSISMessagingProtocolError.invalidLoginResponse
        }
        return APRSISLoginResponse(
            serverCallsign: components[serverIndex + 1]
                .trimmingCharacters(in: CharacterSet(charactersIn: ","))
        )
    }

    func makePacketCommand(_ packet: String) throws -> Data {
        let packetBytes = packet.utf8
        guard
            !packet.isEmpty,
            !packetBytes.contains(13),
            !packetBytes.contains(10),
            packetBytes.count + 2 <= APRSISLineFramer.maximumLineByteCount
        else {
            throw APRSISMessagingProtocolError.invalidPacket
        }
        return Data("\(packet)\r\n".utf8)
    }

    private static func isValidSoftwareToken(_ value: String) -> Bool {
        guard (1 ... 32).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy { byte in
            (48 ... 57).contains(byte)
                || (65 ... 90).contains(byte)
                || (97 ... 122).contains(byte)
                || byte == 45 || byte == 46 || byte == 95
        }
    }
}
