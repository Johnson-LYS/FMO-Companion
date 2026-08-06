import Foundation

nonisolated enum FMOV4ParserError: Error, Equatable, Sendable {
    case wrongDestination
    case missingInternetPath
    case unsupportedFrameType
    case invalidPosition
    case invalidProtocol
    case unsupportedMessageType
    case invalidTokenCount
    case invalidTokenOrder
    case invalidBase64URL
    case invalidCertificateBlob
    case invalidSignature
    case invalidStatusHash
    case invalidNumber
    case invalidText
}

nonisolated enum FMOV4ActivityType: String, Equatable, Sendable {
    case cq = "CQ"
    case omcq = "OMCQ"
    case vocal = "VOCAL"
    case online = "ONLINE"
}

nonisolated struct FMOV4Activity: Equatable, Sendable {
    let type: FMOV4ActivityType
    let serverUID: UInt64
}

nonisolated struct FMOV4Beacon: Equatable, Sendable {
    let frequency: String
    let antennaHeight: UInt32?
    let rigName: String?
    let antennaName: String?
}

nonisolated struct FMOV4Station: Equatable, Sendable {
    let countryCode: String
    let name: String
    let host: String
    let port: UInt16
    let filterKilometers: UInt32
    let onlineUserCount: UInt32
    let peakUserCount: UInt32
}

nonisolated enum FMOV4PositionBody: Equatable, Sendable {
    case activity(FMOV4Activity)
    case beacon(FMOV4Beacon)
    case station(FMOV4Station)
    case joint(statusHash: Data)
}

nonisolated struct UnverifiedFMOV4PositionFrame: Equatable, Sendable {
    let source: TNC2Address
    let latitudeText: String
    let longitudeText: String
    let symbolTable: Character
    let symbolCode: Character
    let certificateBlob: Data
    let signature: Data
    let body: FMOV4PositionBody
}

nonisolated struct UnverifiedFMOV4EventFrame: Equatable, Sendable {
    let source: TNC2Address
    let uid: UInt64
    let topic: String
    let content: String
    let rawStatusPayload: String
}

nonisolated enum UnverifiedFMOV4Frame: Equatable, Sendable {
    case position(UnverifiedFMOV4PositionFrame)
    case event(UnverifiedFMOV4EventFrame)
}

nonisolated struct FMOV4Parser: Sendable {
    func parse(_ packet: TNC2Packet) throws -> UnverifiedFMOV4Frame {
        guard packet.destination == "APFMO4" else {
            throw FMOV4ParserError.wrongDestination
        }
        guard packet.path.contains("TCPIP*") else {
            throw FMOV4ParserError.missingInternetPath
        }

        if packet.information.hasPrefix("=") {
            return .position(try parsePosition(packet))
        }
        if packet.information.hasPrefix(">") {
            return .event(try parseEvent(packet))
        }

        throw FMOV4ParserError.unsupportedFrameType
    }

    private func parsePosition(
        _ packet: TNC2Packet
    ) throws -> UnverifiedFMOV4PositionFrame {
        let bytes = Array(packet.information.utf8)
        guard
            bytes.count > 21,
            bytes[0] == 0x3D,
            bytes[20] == 0x20,
            Self.isPrintableASCII(bytes[9]),
            Self.isPrintableASCII(bytes[19])
        else {
            throw FMOV4ParserError.invalidPosition
        }

        let latitudeText = String(decoding: bytes[1 ..< 9], as: UTF8.self)
        let longitudeText = String(decoding: bytes[10 ..< 19], as: UTF8.self)
        guard
            Self.isValidLatitude(latitudeText),
            Self.isValidLongitude(longitudeText)
        else {
            throw FMOV4ParserError.invalidPosition
        }

        let payload = String(decoding: bytes[21...], as: UTF8.self)
        let tokens = payload.split(
            separator: ",",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard tokens.count >= 2, tokens[0] == "FMO-V4" else {
            throw FMOV4ParserError.invalidProtocol
        }

        let certificateBlob: Data
        let signature: Data
        let body: FMOV4PositionBody

        if let activityType = FMOV4ActivityType(rawValue: tokens[1]) {
            guard tokens.count == 5 else {
                throw FMOV4ParserError.invalidTokenCount
            }
            certificateBlob = try parseCertificate(tokens[2])
            guard tokens[3].hasPrefix("S"), tokens[3].count > 1 else {
                throw FMOV4ParserError.invalidTokenOrder
            }
            let serverText = String(tokens[3].dropFirst())
            guard let serverUID = UInt64(serverText) else {
                throw FMOV4ParserError.invalidNumber
            }
            signature = try parseSignature(tokens[4])
            body = .activity(
                FMOV4Activity(type: activityType, serverUID: serverUID)
            )
        } else {
            switch tokens[1] {
            case "BEACON":
                let parsed = try parseBeacon(tokens)
                certificateBlob = parsed.certificateBlob
                signature = parsed.signature
                body = .beacon(parsed.beacon)
            case "STATION":
                let parsed = try parseStation(tokens)
                certificateBlob = parsed.certificateBlob
                signature = parsed.signature
                body = .station(parsed.station)
            case "JOINT":
                guard tokens.count == 5 else {
                    throw FMOV4ParserError.invalidTokenCount
                }
                certificateBlob = try parseCertificate(tokens[2])
                let statusHash = try parseTaggedBase64URL(
                    tokens[3],
                    prefix: "SH:",
                    requiredByteCount: 32,
                    error: .invalidStatusHash
                )
                signature = try parseSignature(tokens[4])
                body = .joint(statusHash: statusHash)
            default:
                throw FMOV4ParserError.unsupportedMessageType
            }
        }

        return UnverifiedFMOV4PositionFrame(
            source: packet.source,
            latitudeText: latitudeText,
            longitudeText: longitudeText,
            symbolTable: Character(UnicodeScalar(bytes[9])),
            symbolCode: Character(UnicodeScalar(bytes[19])),
            certificateBlob: certificateBlob,
            signature: signature,
            body: body
        )
    }

    private func parseEvent(
        _ packet: TNC2Packet
    ) throws -> UnverifiedFMOV4EventFrame {
        let rawPayload = String(packet.information.dropFirst())
        let tokens = rawPayload.split(
            separator: ",",
            maxSplits: 4,
            omittingEmptySubsequences: false
        ).map(String.init)

        guard tokens.count == 5, tokens[0] == "FMO-V4" else {
            throw FMOV4ParserError.invalidProtocol
        }
        guard tokens[1] == "EVENT" else {
            throw FMOV4ParserError.unsupportedMessageType
        }
        guard let uid = UInt64(tokens[2]) else {
            throw FMOV4ParserError.invalidNumber
        }
        guard
            !tokens[3].isEmpty,
            tokens[3].count <= 32,
            tokens[4].count <= 140
        else {
            throw FMOV4ParserError.invalidText
        }

        return UnverifiedFMOV4EventFrame(
            source: packet.source,
            uid: uid,
            topic: tokens[3],
            content: tokens[4],
            rawStatusPayload: rawPayload
        )
    }

    private func parseBeacon(
        _ tokens: [String]
    ) throws -> (certificateBlob: Data, signature: Data, beacon: FMOV4Beacon) {
        guard (5 ... 8).contains(tokens.count) else {
            throw FMOV4ParserError.invalidTokenCount
        }

        let certificateBlob = try parseCertificate(tokens[2])
        guard tokens[3].hasPrefix("FREQ:") else {
            throw FMOV4ParserError.invalidTokenOrder
        }
        let frequency = String(tokens[3].dropFirst("FREQ:".count))
        guard Self.isValidFrequency(frequency) else {
            throw FMOV4ParserError.invalidNumber
        }

        var antennaHeight: UInt32?
        var rigName: String?
        var antennaName: String?
        var nextOptionalField = 0

        for token in tokens.dropFirst(4).dropLast() {
            if token.hasPrefix("HEIGHT:"), nextOptionalField <= 0 {
                guard
                    let value = UInt32(token.dropFirst("HEIGHT:".count)),
                    value > 0
                else {
                    throw FMOV4ParserError.invalidNumber
                }
                antennaHeight = value
                nextOptionalField = 1
            } else if token.hasPrefix("RIG:"), nextOptionalField <= 1 {
                let value = String(token.dropFirst("RIG:".count))
                try validateText(value, maximumUTF8ByteCount: 64)
                rigName = value
                nextOptionalField = 2
            } else if token.hasPrefix("ANT:"), nextOptionalField <= 2 {
                let value = String(token.dropFirst("ANT:".count))
                try validateText(value, maximumUTF8ByteCount: 64)
                antennaName = value
                nextOptionalField = 3
            } else {
                throw FMOV4ParserError.invalidTokenOrder
            }
        }

        let signature = try parseSignature(tokens[tokens.count - 1])
        return (
            certificateBlob,
            signature,
            FMOV4Beacon(
                frequency: frequency,
                antennaHeight: antennaHeight,
                rigName: rigName,
                antennaName: antennaName
            )
        )
    }

    private func parseStation(
        _ tokens: [String]
    ) throws -> (certificateBlob: Data, signature: Data, station: FMOV4Station) {
        guard tokens.count == 10 else {
            throw FMOV4ParserError.invalidTokenCount
        }

        let certificateBlob = try parseCertificate(tokens[2])
        let countryCode = tokens[3]
        guard
            countryCode.utf8.count == 2,
            countryCode.utf8.allSatisfy({ (65 ... 90).contains($0) })
        else {
            throw FMOV4ParserError.invalidText
        }

        try validateText(tokens[4], maximumUTF8ByteCount: 64)
        try validateText(tokens[5], maximumUTF8ByteCount: 253)
        guard !tokens[5].contains(where: { $0.isWhitespace }) else {
            throw FMOV4ParserError.invalidText
        }

        guard
            tokens[6].hasPrefix("P"),
            let port = UInt16(tokens[6].dropFirst()),
            port > 0,
            tokens[7].hasPrefix("F"),
            tokens[7].hasSuffix("KM"),
            let filterKilometers = UInt32(tokens[7].dropFirst().dropLast(2)),
            filterKilometers <= 50_000,
            tokens[8].hasPrefix("U")
        else {
            throw FMOV4ParserError.invalidNumber
        }

        let userCounts = tokens[8].dropFirst().split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard
            userCounts.count == 2,
            let onlineUserCount = UInt32(userCounts[0]),
            let peakUserCount = UInt32(userCounts[1]),
            onlineUserCount <= peakUserCount
        else {
            throw FMOV4ParserError.invalidNumber
        }

        let signature = try parseSignature(tokens[9])
        return (
            certificateBlob,
            signature,
            FMOV4Station(
                countryCode: countryCode,
                name: tokens[4],
                host: tokens[5],
                port: port,
                filterKilometers: filterKilometers,
                onlineUserCount: onlineUserCount,
                peakUserCount: peakUserCount
            )
        )
    }

    private func parseCertificate(_ token: String) throws -> Data {
        guard token.hasPrefix("CERT:") else {
            throw FMOV4ParserError.invalidTokenOrder
        }
        let data = try decodeBase64URL(String(token.dropFirst("CERT:".count)))
        guard (1 ... 256).contains(data.count) else {
            throw FMOV4ParserError.invalidCertificateBlob
        }
        return data
    }

    private func parseSignature(_ token: String) throws -> Data {
        try parseTaggedBase64URL(
            token,
            prefix: "SIG:",
            requiredByteCount: 64,
            error: .invalidSignature
        )
    }

    private func parseTaggedBase64URL(
        _ token: String,
        prefix: String,
        requiredByteCount: Int,
        error: FMOV4ParserError
    ) throws -> Data {
        guard token.hasPrefix(prefix) else {
            throw FMOV4ParserError.invalidTokenOrder
        }
        let data = try decodeBase64URL(String(token.dropFirst(prefix.count)))
        guard data.count == requiredByteCount else {
            throw error
        }
        return data
    }

    private func decodeBase64URL(_ value: String) throws -> Data {
        guard !value.isEmpty else {
            throw FMOV4ParserError.invalidBase64URL
        }

        let paddingStart = value.firstIndex(of: "=")
        if let paddingStart {
            let padding = value[paddingStart...]
            guard
                padding.count <= 2,
                padding.allSatisfy({ $0 == "=" })
            else {
                throw FMOV4ParserError.invalidBase64URL
            }
        }

        let unpadded = paddingStart.map { String(value[..<$0]) } ?? value
        guard
            unpadded.utf8.allSatisfy(Self.isBase64URLByte),
            unpadded.utf8.count % 4 != 1
        else {
            throw FMOV4ParserError.invalidBase64URL
        }

        let standard = unpadded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let requiredPadding = (4 - standard.utf8.count % 4) % 4
        let padded = standard + String(repeating: "=", count: requiredPadding)
        guard let data = Data(base64Encoded: padded) else {
            throw FMOV4ParserError.invalidBase64URL
        }
        return data
    }

    private func validateText(
        _ value: String,
        maximumUTF8ByteCount: Int
    ) throws {
        guard
            !value.isEmpty,
            value.utf8.count <= maximumUTF8ByteCount
        else {
            throw FMOV4ParserError.invalidText
        }
    }

    private static func isValidLatitude(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard
            bytes.count == 8,
            bytes[0 ... 3].allSatisfy(isASCIIDigit),
            bytes[4] == 0x2E,
            bytes[5 ... 6].allSatisfy(isASCIIDigit),
            bytes[7] == 0x4E || bytes[7] == 0x53,
            let degrees = Int(String(decoding: bytes[0 ... 1], as: UTF8.self)),
            let minutes = Double(String(decoding: bytes[2 ... 6], as: UTF8.self)),
            degrees <= 90,
            minutes < 60,
            degrees < 90 || minutes == 0
        else {
            return false
        }
        return true
    }

    private static func isValidLongitude(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard
            bytes.count == 9,
            bytes[0 ... 4].allSatisfy(isASCIIDigit),
            bytes[5] == 0x2E,
            bytes[6 ... 7].allSatisfy(isASCIIDigit),
            bytes[8] == 0x45 || bytes[8] == 0x57,
            let degrees = Int(String(decoding: bytes[0 ... 2], as: UTF8.self)),
            let minutes = Double(String(decoding: bytes[3 ... 7], as: UTF8.self)),
            degrees <= 180,
            minutes < 60,
            degrees < 180 || minutes == 0
        else {
            return false
        }
        return true
    }

    private static func isValidFrequency(_ value: String) -> Bool {
        let components = value.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard
            components.count == 2,
            (1 ... 3).contains(components[0].utf8.count),
            components[0].utf8.allSatisfy(isASCIIDigit),
            components[1].utf8.count == 4,
            components[1].utf8.allSatisfy(isASCIIDigit),
            let frequency = Double(value),
            frequency > 0,
            frequency <= 1_000
        else {
            return false
        }
        return true
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        (48 ... 57).contains(byte)
    }

    private static func isPrintableASCII(_ byte: UInt8) -> Bool {
        (33 ... 126).contains(byte)
    }

    private static func isBase64URLByte(_ byte: UInt8) -> Bool {
        (48 ... 57).contains(byte)
            || (65 ... 90).contains(byte)
            || (97 ... 122).contains(byte)
            || byte == 45
            || byte == 95
    }
}
