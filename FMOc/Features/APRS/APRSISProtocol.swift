import Foundation

nonisolated enum APRSISProtocolError: Error, Equatable, Sendable {
    case invalidSoftwareName
    case invalidSoftwareVersion
    case invalidLoginResponse
    case loginIdentityMismatch
    case unexpectedVerificationStatus
}

nonisolated struct APRSISLoginResponse: Equatable, Sendable {
    let serverCallsign: String
}

nonisolated struct APRSISProtocol: Sendable {
    static let receiveOnlyPasscode = "-1"
    static let fmoV4Filter = "u/APFMO4"

    private let softwareName: String
    private let softwareVersion: String

    init(softwareName: String, softwareVersion: String) throws {
        guard Self.isValidSoftwareToken(softwareName) else {
            throw APRSISProtocolError.invalidSoftwareName
        }
        guard Self.isValidSoftwareToken(softwareVersion) else {
            throw APRSISProtocolError.invalidSoftwareVersion
        }

        self.softwareName = softwareName
        self.softwareVersion = softwareVersion
    }

    func makeLoginCommand(for identity: ReceiveOnlyAPRSIdentity) -> Data {
        let line = [
            "user", identity.loginCallsign,
            "pass", Self.receiveOnlyPasscode,
            "vers", softwareName, softwareVersion,
            "filter", Self.fmoV4Filter,
        ].joined(separator: " ")

        return Data("\(line)\r\n".utf8)
    }

    func parseLoginResponse(
        _ line: String,
        expectedIdentity: ReceiveOnlyAPRSIdentity
    ) throws -> APRSISLoginResponse {
        let components = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard
            components.count >= 4,
            components[0] == "#",
            components[1].lowercased() == "logresp"
        else {
            throw APRSISProtocolError.invalidLoginResponse
        }

        guard components[2].uppercased() == expectedIdentity.loginCallsign else {
            throw APRSISProtocolError.loginIdentityMismatch
        }

        let status = components[3]
            .trimmingCharacters(in: CharacterSet(charactersIn: ","))
            .lowercased()
        guard status == "unverified" else {
            throw APRSISProtocolError.unexpectedVerificationStatus
        }

        let serverCallsign = components.indices
            .dropFirst(4)
            .first(where: { components[$0].lowercased() == "server" })
            .flatMap { serverIndex -> String? in
                let valueIndex = serverIndex + 1
                guard components.indices.contains(valueIndex) else { return nil }
                let value = components[valueIndex]
                    .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                return value.isEmpty ? nil : value
            }
        guard let serverCallsign else {
            throw APRSISProtocolError.invalidLoginResponse
        }

        return APRSISLoginResponse(serverCallsign: serverCallsign)
    }

    private static func isValidSoftwareToken(_ value: String) -> Bool {
        guard (1 ... 32).contains(value.utf8.count) else { return false }

        return value.utf8.allSatisfy { byte in
            (48 ... 57).contains(byte)
                || (65 ... 90).contains(byte)
                || (97 ... 122).contains(byte)
                || byte == 45
                || byte == 46
                || byte == 95
        }
    }
}
