import Foundation

nonisolated enum FMORawError: Error, Equatable, Sendable {
    case payloadSize
    case unsupportedVersion
    case invalidVendor
    case invalidLength
    case invalidCallsign
    case invalidFrameCount
    case checksumMismatch
    case truncatedFrame
    case invalidFrameIndex
    case unsupportedCodec(UInt8)
    case emptyCodecPayload
    case trailingBytes
}

nonisolated enum FMOVoiceCodec: UInt8, Sendable {
    case opus = 1
    case radpcm = 2
}

nonisolated struct FMORawHeader: Equatable, Sendable {
    static let byteCount = 64
    static let maximumPacketByteCount = 1_400

    let version: UInt16
    let vendor: UInt32
    let uid: UInt32
    let callsign: String
    let streamBeginUTC: UInt32
    let timestamp: UInt32
    let frameCount: UInt16
    let signalMeter: UInt8
    let serverUID: UInt32
}

nonisolated struct FMORawCodedFrame: Equatable, Sendable {
    let codec: FMOVoiceCodec
    let payload: Data
}

nonisolated struct FMORawPacket: Equatable, Sendable {
    let header: FMORawHeader
    let frames: [FMORawCodedFrame]
}

nonisolated struct FMORawParser: Sendable {
    func parse(_ data: Data) throws -> FMORawPacket {
        guard (FMORawHeader.byteCount ... FMORawHeader.maximumPacketByteCount).contains(data.count) else {
            throw FMORawError.payloadSize
        }
        var reader = FMOLittleEndianReader(data: data)
        let version = try reader.readUInt16()
        guard version == 1 else { throw FMORawError.unsupportedVersion }
        let vendor = try reader.readUInt32()
        guard (0 ... 0x2FFF).contains(vendor) else { throw FMORawError.invalidVendor }
        let uid = try reader.readUInt32()
        let callsignBytes = try reader.readData(count: 12)
        guard let callsign = Self.decodeCallsign(callsignBytes) else {
            throw FMORawError.invalidCallsign
        }
        let streamBeginUTC = try reader.readUInt32()
        let timestamp = try reader.readUInt32()
        let declaredLength = try reader.readUInt32()
        guard declaredLength == UInt32(data.count) else { throw FMORawError.invalidLength }
        let frameCount = try reader.readUInt16()
        guard frameCount > 0 else { throw FMORawError.invalidFrameCount }
        let checksum = try reader.readUInt32()
        let signalMeter = try reader.readUInt8()
        let serverUID = try reader.readUInt32()
        _ = try reader.readData(count: 19)

        let frameArea = data.subdata(in: FMORawHeader.byteCount ..< data.count)
        guard FMOCRC32.checksum(frameArea) == checksum else {
            throw FMORawError.checksumMismatch
        }

        var frames: [FMORawCodedFrame] = []
        frames.reserveCapacity(Int(frameCount))
        for expectedIndex in 1 ... frameCount {
            let index = try reader.readUInt16(or: .truncatedFrame)
            guard index == expectedIndex else { throw FMORawError.invalidFrameIndex }
            let transportLength = try reader.readUInt16(or: .truncatedFrame)
            guard transportLength >= 16 else { throw FMORawError.invalidLength }
            _ = try reader.readUInt32(or: .truncatedFrame)
            let codedLength = Int(transportLength) - 8
            let codedData = try reader.readData(count: codedLength, or: .truncatedFrame)
            var codedReader = FMOLittleEndianReader(data: codedData)
            let codecRaw = try codedReader.readUInt8(or: .truncatedFrame)
            guard let codec = FMOVoiceCodec(rawValue: codecRaw) else {
                throw FMORawError.unsupportedCodec(codecRaw)
            }
            let declaredCodedLength = try codedReader.readUInt16(or: .truncatedFrame)
            guard declaredCodedLength == UInt16(codedLength), declaredCodedLength >= 8 else {
                throw FMORawError.invalidLength
            }
            _ = try codedReader.readData(count: 5, or: .truncatedFrame)
            let payload = try codedReader.readData(count: codedReader.remaining, or: .truncatedFrame)
            guard !payload.isEmpty else { throw FMORawError.emptyCodecPayload }
            frames.append(FMORawCodedFrame(codec: codec, payload: payload))
        }
        guard reader.remaining == 0 else { throw FMORawError.trailingBytes }

        return FMORawPacket(
            header: FMORawHeader(
                version: version,
                vendor: vendor,
                uid: uid,
                callsign: callsign,
                streamBeginUTC: streamBeginUTC,
                timestamp: timestamp,
                frameCount: frameCount,
                signalMeter: signalMeter,
                serverUID: serverUID
            ),
            frames: frames
        )
    }

    private static func decodeCallsign(_ data: Data) -> String? {
        let bytes = Array(data)
        let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
        guard bytes[end...].allSatisfy({ $0 == 0 }), end > 0 else { return nil }
        let value = String(decoding: bytes[..<end], as: UTF8.self).uppercased()
        guard value.utf8.count <= 12, value.utf8.allSatisfy({ byte in
            (48 ... 57).contains(byte) || (65 ... 90).contains(byte) || byte == 45
        }) else { return nil }
        return value
    }
}

nonisolated struct FMORawEncoder: Sendable {
    let softwareVendor: UInt32

    init(softwareVendor: UInt32 = 0x2000) {
        self.softwareVendor = softwareVendor
    }

    func encode(
        uid: UInt32,
        callsign: String,
        streamBeginUTC: UInt32,
        timestamp: UInt32,
        serverUID: UInt32,
        frames: [Data]
    ) throws -> Data {
        guard (0x2000 ... 0x2FFF).contains(softwareVendor), !frames.isEmpty else {
            throw FMORawError.invalidVendor
        }
        let normalizedCallsign = callsign.uppercased()
        guard !normalizedCallsign.isEmpty, normalizedCallsign.utf8.count <= 12,
              normalizedCallsign.utf8.allSatisfy({ byte in
                  (48 ... 57).contains(byte) || (65 ... 90).contains(byte) || byte == 45
              }) else { throw FMORawError.invalidCallsign }

        var frameArea = Data()
        for (offset, payload) in frames.enumerated() {
            guard !payload.isEmpty else { throw FMORawError.emptyCodecPayload }
            let codedLength = 8 + payload.count
            let transportLength = 8 + codedLength
            guard transportLength <= Int(UInt16.max) else { throw FMORawError.invalidLength }
            frameArea.appendLittleEndian(UInt16(offset + 1))
            frameArea.appendLittleEndian(UInt16(transportLength))
            frameArea.appendLittleEndian(UInt32(0))
            frameArea.append(FMOVoiceCodec.opus.rawValue)
            frameArea.appendLittleEndian(UInt16(codedLength))
            frameArea.append(Data(repeating: 0, count: 5))
            frameArea.append(payload)
        }
        let totalLength = FMORawHeader.byteCount + frameArea.count
        guard totalLength <= FMORawHeader.maximumPacketByteCount else { throw FMORawError.payloadSize }

        var output = Data()
        output.appendLittleEndian(UInt16(1))
        output.appendLittleEndian(softwareVendor)
        output.appendLittleEndian(uid)
        output.append(Data(normalizedCallsign.utf8))
        output.append(Data(repeating: 0, count: 12 - normalizedCallsign.utf8.count))
        output.appendLittleEndian(streamBeginUTC)
        output.appendLittleEndian(timestamp)
        output.appendLittleEndian(UInt32(totalLength))
        output.appendLittleEndian(UInt16(frames.count))
        output.appendLittleEndian(FMOCRC32.checksum(frameArea))
        output.append(0)
        output.appendLittleEndian(serverUID)
        output.append(Data(repeating: 0, count: 19))
        output.append(frameArea)
        return output
    }
}

private nonisolated struct FMOLittleEndianReader {
    let data: Data
    var offset = 0
    var remaining: Int { data.count - offset }

    mutating func readUInt8(or error: FMORawError = .payloadSize) throws -> UInt8 {
        guard remaining >= 1 else { throw error }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16(or error: FMORawError = .payloadSize) throws -> UInt16 {
        let bytes = try readData(count: 2, or: error)
        return UInt16(bytes[bytes.startIndex]) | UInt16(bytes[bytes.startIndex + 1]) << 8
    }

    mutating func readUInt32(or error: FMORawError = .payloadSize) throws -> UInt32 {
        let bytes = try readData(count: 4, or: error)
        return bytes.enumerated().reduce(into: UInt32.zero) { result, item in
            result |= UInt32(item.element) << UInt32(item.offset * 8)
        }
    }

    mutating func readData(count: Int, or error: FMORawError = .payloadSize) throws -> Data {
        guard count >= 0, remaining >= count else { throw error }
        defer { offset += count }
        return data.subdata(in: offset ..< offset + count)
    }
}

private nonisolated extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
