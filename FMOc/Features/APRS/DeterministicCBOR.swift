import Foundation

nonisolated enum DeterministicCBORValue: Equatable, Sendable {
    case unsigned(UInt64)
    case bytes(Data)
    case text(String)
    case array([DeterministicCBORValue])
    case boolean(Bool)
}

nonisolated enum DeterministicCBORError: Error, Equatable, Sendable {
    case truncated
    case unsupportedType
    case nonCanonical
    case invalidUTF8
    case excessiveDepth
    case excessiveLength
    case trailingBytes
}

nonisolated struct DeterministicCBOR: Sendable {
    struct Limits: Sendable {
        var maximumDepth = 4
        var maximumArrayCount = 64
        var maximumByteStringLength = 512
        var maximumTextByteCount = 1_024
    }

    let limits: Limits

    init(limits: Limits = Limits()) {
        self.limits = limits
    }

    func encode(_ value: DeterministicCBORValue) throws -> Data {
        var output = Data()
        try encode(value, depth: 0, into: &output)
        return output
    }

    func decode(_ data: Data) throws -> DeterministicCBORValue {
        var reader = Reader(data: data, limits: limits)
        let value = try reader.readValue(depth: 0)
        guard reader.isAtEnd else {
            throw DeterministicCBORError.trailingBytes
        }
        return value
    }

    private func encode(
        _ value: DeterministicCBORValue,
        depth: Int,
        into output: inout Data
    ) throws {
        guard depth <= limits.maximumDepth else {
            throw DeterministicCBORError.excessiveDepth
        }

        switch value {
        case .unsigned(let value):
            appendHeader(majorType: 0, value: value, into: &output)
        case .bytes(let data):
            guard data.count <= limits.maximumByteStringLength else {
                throw DeterministicCBORError.excessiveLength
            }
            appendHeader(majorType: 2, value: UInt64(data.count), into: &output)
            output.append(data)
        case .text(let string):
            let data = Data(string.utf8)
            guard data.count <= limits.maximumTextByteCount else {
                throw DeterministicCBORError.excessiveLength
            }
            appendHeader(majorType: 3, value: UInt64(data.count), into: &output)
            output.append(data)
        case .array(let values):
            guard values.count <= limits.maximumArrayCount else {
                throw DeterministicCBORError.excessiveLength
            }
            appendHeader(majorType: 4, value: UInt64(values.count), into: &output)
            for value in values {
                try encode(value, depth: depth + 1, into: &output)
            }
        case .boolean(let value):
            output.append(value ? 0xF5 : 0xF4)
        }
    }

    private func appendHeader(majorType: UInt8, value: UInt64, into output: inout Data) {
        let prefix = majorType << 5
        switch value {
        case 0 ... 23:
            output.append(prefix | UInt8(value))
        case 24 ... 0xFF:
            output.append(prefix | 24)
            output.append(UInt8(value))
        case 0x100 ... 0xFFFF:
            output.append(prefix | 25)
            appendBigEndian(UInt16(value), into: &output)
        case 0x1_0000 ... 0xFFFF_FFFF:
            output.append(prefix | 26)
            appendBigEndian(UInt32(value), into: &output)
        default:
            output.append(prefix | 27)
            appendBigEndian(value, into: &output)
        }
    }

    private func appendBigEndian<T: FixedWidthInteger>(_ value: T, into output: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { output.append(contentsOf: $0) }
    }

    private struct Reader {
        let data: Data
        let limits: Limits
        var offset = 0

        var isAtEnd: Bool { offset == data.count }

        mutating func readValue(depth: Int) throws -> DeterministicCBORValue {
            guard depth <= limits.maximumDepth else {
                throw DeterministicCBORError.excessiveDepth
            }
            let initial = try readByte()
            let majorType = initial >> 5
            let additional = initial & 0x1F

            if majorType == 7 {
                switch additional {
                case 20:
                    return .boolean(false)
                case 21:
                    return .boolean(true)
                default:
                    throw DeterministicCBORError.unsupportedType
                }
            }

            let value = try readLength(additional)
            switch majorType {
            case 0:
                return .unsigned(value)
            case 2:
                guard value <= UInt64(limits.maximumByteStringLength) else {
                    throw DeterministicCBORError.excessiveLength
                }
                return .bytes(try readData(count: Int(value)))
            case 3:
                guard value <= UInt64(limits.maximumTextByteCount) else {
                    throw DeterministicCBORError.excessiveLength
                }
                let bytes = try readData(count: Int(value))
                guard let string = String(data: bytes, encoding: .utf8) else {
                    throw DeterministicCBORError.invalidUTF8
                }
                return .text(string)
            case 4:
                guard value <= UInt64(limits.maximumArrayCount) else {
                    throw DeterministicCBORError.excessiveLength
                }
                var values: [DeterministicCBORValue] = []
                values.reserveCapacity(Int(value))
                for _ in 0 ..< value {
                    values.append(try readValue(depth: depth + 1))
                }
                return .array(values)
            default:
                throw DeterministicCBORError.unsupportedType
            }
        }

        private mutating func readLength(_ additional: UInt8) throws -> UInt64 {
            switch additional {
            case 0 ... 23:
                return UInt64(additional)
            case 24:
                let value = UInt64(try readByte())
                guard value >= 24 else { throw DeterministicCBORError.nonCanonical }
                return value
            case 25:
                let value = UInt64(try readInteger(UInt16.self))
                guard value > 0xFF else { throw DeterministicCBORError.nonCanonical }
                return value
            case 26:
                let value = UInt64(try readInteger(UInt32.self))
                guard value > 0xFFFF else { throw DeterministicCBORError.nonCanonical }
                return value
            case 27:
                let value = try readInteger(UInt64.self)
                guard value > 0xFFFF_FFFF else { throw DeterministicCBORError.nonCanonical }
                return value
            default:
                throw DeterministicCBORError.unsupportedType
            }
        }

        private mutating func readByte() throws -> UInt8 {
            guard offset < data.count else { throw DeterministicCBORError.truncated }
            defer { offset += 1 }
            return data[offset]
        }

        private mutating func readData(count: Int) throws -> Data {
            guard count >= 0, offset <= data.count - count else {
                throw DeterministicCBORError.truncated
            }
            defer { offset += count }
            return data.subdata(in: offset ..< offset + count)
        }

        private mutating func readInteger<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
            let bytes = try readData(count: MemoryLayout<T>.size)
            return bytes.reduce(into: T.zero) { result, byte in
                result = (result << 8) | T(byte)
            }
        }
    }
}
