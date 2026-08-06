import Foundation

nonisolated enum TNC2PacketError: Error, Equatable, Sendable {
    case lineTooLong
    case serverComment
    case malformedHeader
    case invalidSource
    case invalidSSID
    case invalidDestination
    case invalidPath
    case emptyInformation
}

nonisolated struct TNC2Address: Equatable, Hashable, Sendable {
    let callsign: String
    let ssid: UInt8

    var formatted: String {
        ssid == 0 ? callsign : "\(callsign)-\(ssid)"
    }
}

nonisolated struct TNC2Packet: Equatable, Sendable {
    let source: TNC2Address
    let destination: String
    let path: [String]
    let information: String
}

nonisolated struct TNC2PacketParser: Sendable {
    func parse(_ line: String) throws -> TNC2Packet {
        guard line.utf8.count + 2 <= APRSISLineFramer.maximumLineByteCount else {
            throw TNC2PacketError.lineTooLong
        }
        guard !line.hasPrefix("#") else {
            throw TNC2PacketError.serverComment
        }

        guard
            let sourceSeparator = line.firstIndex(of: ">"),
            let informationSeparator = line[sourceSeparator...].firstIndex(of: ":"),
            sourceSeparator != line.startIndex
        else {
            throw TNC2PacketError.malformedHeader
        }

        let sourceText = String(line[..<sourceSeparator])
        let routeStart = line.index(after: sourceSeparator)
        let routeText = String(line[routeStart..<informationSeparator])
        let informationStart = line.index(after: informationSeparator)
        let information = String(line[informationStart...])

        guard !information.isEmpty else {
            throw TNC2PacketError.emptyInformation
        }

        let source = try parseSource(sourceText)
        let route = routeText.split(separator: ",", omittingEmptySubsequences: false)
        guard let destinationText = route.first, !destinationText.isEmpty else {
            throw TNC2PacketError.invalidDestination
        }

        let destination = String(destinationText).uppercased()
        guard
            destination.utf8.count <= 9,
            destination.utf8.allSatisfy(Self.isASCIIAlphanumeric)
        else {
            throw TNC2PacketError.invalidDestination
        }

        let path = try route.dropFirst().map { component -> String in
            let value = String(component).uppercased()
            guard
                !value.isEmpty,
                value.utf8.count <= 10,
                value.utf8.allSatisfy(Self.isValidPathByte)
            else {
                throw TNC2PacketError.invalidPath
            }
            return value
        }

        return TNC2Packet(
            source: source,
            destination: destination,
            path: path,
            information: information
        )
    }

    private func parseSource(_ value: String) throws -> TNC2Address {
        let components = value.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let callsign = String(components[0]).uppercased()

        guard
            callsign.utf8.count >= 3,
            callsign.utf8.allSatisfy(Self.isASCIIAlphanumeric)
        else {
            throw TNC2PacketError.invalidSource
        }

        let ssid: UInt8
        if components.count == 2 {
            guard
                !components[1].isEmpty,
                let parsedSSID = UInt8(components[1]),
                parsedSSID <= 15
            else {
                throw TNC2PacketError.invalidSSID
            }
            ssid = parsedSSID
        } else {
            ssid = 0
        }

        let address = TNC2Address(callsign: callsign, ssid: ssid)
        guard address.formatted.utf8.count <= 9 else {
            throw TNC2PacketError.invalidSource
        }
        return address
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (48 ... 57).contains(byte) || (65 ... 90).contains(byte)
    }

    private static func isValidPathByte(_ byte: UInt8) -> Bool {
        isASCIIAlphanumeric(byte) || byte == 42 || byte == 45
    }
}
