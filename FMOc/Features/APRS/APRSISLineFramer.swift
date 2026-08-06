import Foundation

nonisolated enum APRSISLineFramerError: Error, Equatable, Sendable {
    case emptyLine
    case invalidLineEnding
    case invalidUTF8
    case lineTooLong
}

nonisolated struct APRSISLineFramer: Sendable {
    static let maximumLineByteCount = 512

    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [String] {
        buffer.append(data)

        do {
            return try extractCompleteLines()
        } catch {
            buffer.removeAll(keepingCapacity: true)
            throw error
        }
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    private mutating func extractCompleteLines() throws -> [String] {
        var lines: [String] = []

        while let lineFeedIndex = buffer.firstIndex(of: 0x0A) {
            guard lineFeedIndex > buffer.startIndex else {
                throw APRSISLineFramerError.invalidLineEnding
            }

            let carriageReturnIndex = buffer.index(before: lineFeedIndex)
            guard buffer[carriageReturnIndex] == 0x0D else {
                throw APRSISLineFramerError.invalidLineEnding
            }

            let lineData = buffer[..<carriageReturnIndex]
            guard !lineData.contains(0x0D) else {
                throw APRSISLineFramerError.invalidLineEnding
            }
            guard lineData.count + 2 <= Self.maximumLineByteCount else {
                throw APRSISLineFramerError.lineTooLong
            }
            guard !lineData.isEmpty else {
                throw APRSISLineFramerError.emptyLine
            }
            guard let line = String(data: lineData, encoding: .utf8) else {
                throw APRSISLineFramerError.invalidUTF8
            }

            lines.append(line)
            buffer.removeSubrange(...lineFeedIndex)
        }

        if let carriageReturnIndex = buffer.firstIndex(of: 0x0D) {
            guard carriageReturnIndex == buffer.index(before: buffer.endIndex) else {
                throw APRSISLineFramerError.invalidLineEnding
            }
        }

        let maximumPendingByteCount = buffer.last == 0x0D
            ? Self.maximumLineByteCount - 1
            : Self.maximumLineByteCount - 2
        guard buffer.count <= maximumPendingByteCount else {
            throw APRSISLineFramerError.lineTooLong
        }

        return lines
    }
}
