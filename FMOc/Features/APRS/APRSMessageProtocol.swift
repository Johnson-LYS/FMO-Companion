import Foundation

nonisolated enum APRSMessageProtocolError: Error, Equatable, Sendable {
    case invalidAddress
    case emptyText
    case textTooLong
    case unsupportedTextCharacter
    case invalidText
    case invalidMessageID
    case malformedInformation
    case wrongAddressee
}

nonisolated struct APRSMessageID: Equatable, Hashable, Sendable, Codable {
    let rawValue: String

    init(_ rawValue: String) throws {
        let normalized = rawValue.uppercased()
        guard
            (1 ... 5).contains(normalized.utf8.count),
            normalized.utf8.allSatisfy(Self.isASCIIAlphanumeric)
        else {
            throw APRSMessageProtocolError.invalidMessageID
        }
        self.rawValue = normalized
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (48 ... 57).contains(byte) || (65 ... 90).contains(byte)
    }
}

nonisolated enum APRSMessagePayload: Equatable, Sendable {
    case message(text: String, id: APRSMessageID?)
    case acknowledgement(APRSMessageID)
    case rejection(APRSMessageID)
}

nonisolated struct APRSMessageEnvelope: Equatable, Sendable {
    let source: TNC2Address
    let addressee: TNC2Address
    let payload: APRSMessagePayload
}

nonisolated struct APRSMessageCodec: Sendable {
    // FMO 的消息服务与远控共用 APFMO0 TOCALL。使用其他自定义
    // TOCALL 会使消息在到达目标 FMO 前被其 APRS 订阅过滤掉。
    static let applicationDestination = "APFMO0"
    static let path = ["TCPIP*"]
    static let maximumTextByteCount = 60

    func encodeInformation(
        addressee: TNC2Address,
        payload: APRSMessagePayload
    ) throws -> String {
        let paddedAddressee = try paddedAddress(addressee)
        let body: String

        switch payload {
        case let .message(text, id):
            try validateText(text)
            body = id.map { "\(text){\($0.rawValue)" } ?? text
        case let .acknowledgement(id):
            body = "ack\(id.rawValue)"
        case let .rejection(id):
            body = "rej\(id.rawValue)"
        }

        return ":\(paddedAddressee):\(body)"
    }

    func encodePacket(
        source: TNC2Address,
        addressee: TNC2Address,
        payload: APRSMessagePayload
    ) throws -> String {
        try validateAddress(source)
        let information = try encodeInformation(addressee: addressee, payload: payload)
        let route = ([Self.applicationDestination] + Self.path).joined(separator: ",")
        let packet = "\(source.formatted)>\(route):\(information)"
        guard packet.utf8.count + 2 <= APRSISLineFramer.maximumLineByteCount else {
            throw APRSMessageProtocolError.invalidText
        }
        return String(packet)
    }

    func decode(
        _ packet: TNC2Packet,
        expectedAddressee: TNC2Address? = nil
    ) throws -> APRSMessageEnvelope {
        let bytes = Array(packet.information.utf8)
        guard bytes.count >= 12, bytes[0] == 58, bytes[10] == 58 else {
            throw APRSMessageProtocolError.malformedInformation
        }

        let addressText = String(decoding: bytes[1 ... 9], as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        let addressee = try parseAddress(addressText)
        if let expectedAddressee, addressee != expectedAddressee {
            throw APRSMessageProtocolError.wrongAddressee
        }

        let body = String(decoding: bytes.dropFirst(11), as: UTF8.self)
        guard !body.isEmpty else {
            throw APRSMessageProtocolError.malformedInformation
        }

        let payload: APRSMessagePayload
        if body.hasPrefix("ack") {
            payload = .acknowledgement(try APRSMessageID(String(body.dropFirst(3))))
        } else if body.hasPrefix("rej") {
            payload = .rejection(try APRSMessageID(String(body.dropFirst(3))))
        } else if let separator = body.lastIndex(of: "{") {
            let text = String(body[..<separator])
            let id = try APRSMessageID(String(body[body.index(after: separator)...]))
            try validateText(text)
            payload = .message(text: text, id: id)
        } else {
            try validateText(body)
            payload = .message(text: body, id: nil)
        }

        return APRSMessageEnvelope(
            source: packet.source,
            addressee: addressee,
            payload: payload
        )
    }

    private func paddedAddress(_ address: TNC2Address) throws -> String {
        try validateAddress(address)
        return address.formatted.padding(toLength: 9, withPad: " ", startingAt: 0)
    }

    private func validateAddress(_ address: TNC2Address) throws {
        guard
            (3 ... 9).contains(address.formatted.utf8.count),
            address.ssid <= 15,
            address.callsign.utf8.allSatisfy(Self.isASCIIAlphanumeric)
        else {
            throw APRSMessageProtocolError.invalidAddress
        }
    }

    func parseAddress(_ text: String) throws -> TNC2Address {
        let components = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard !components.isEmpty else { throw APRSMessageProtocolError.invalidAddress }
        let callsign = String(components[0]).uppercased()
        let ssid: UInt8
        if components.count == 2 {
            guard let value = UInt8(components[1]), value <= 15 else {
                throw APRSMessageProtocolError.invalidAddress
            }
            ssid = value
        } else {
            ssid = 0
        }
        let address = TNC2Address(callsign: callsign, ssid: ssid)
        try validateAddress(address)
        return address
    }

    private func validateText(_ text: String) throws {
        guard !text.isEmpty else { throw APRSMessageProtocolError.emptyText }
        guard text.utf8.count <= Self.maximumTextByteCount else {
            throw APRSMessageProtocolError.textTooLong
        }
        guard !text.unicodeScalars.contains(where: { scalar in
            scalar.value < 0x20
                || (0x7F ... 0x9F).contains(scalar.value)
                || scalar.value == 0x7B
        }) else {
            throw APRSMessageProtocolError.unsupportedTextCharacter
        }
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (48 ... 57).contains(byte) || (65 ... 90).contains(byte)
    }
}
