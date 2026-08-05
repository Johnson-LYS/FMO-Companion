import Foundation

nonisolated struct FmoSpeakingState: Equatable, Sendable {
    let callsign: String?
    let grid: String?
    let isSpeaking: Bool
    let sequence: UInt64
    let deviceUptimeMilliseconds: UInt64
}

nonisolated struct FmoRecentLocalActivity: Equatable, Sendable {
    let callsign: String
    let occurredAt: Date
}

nonisolated enum FmoLocalEvent: Equatable, Sendable {
    case speaking(FmoSpeakingState)
    case history([FmoRecentLocalActivity])
}

nonisolated struct FmoLocalEventProtocol: Sendable {
    private struct Header: Decodable, Sendable {
        let type: String
        let subType: String
    }

    private struct SpeakingEnvelope: Decodable, Sendable {
        struct Payload: Decodable, Sendable {
            let callsign: String
            let grid: String?
            let isSpeaking: Bool
        }

        let type: String
        let subType: String
        let seq: UInt64
        let ts: UInt64
        let data: Payload
    }

    private struct HistoryEnvelope: Decodable, Sendable {
        struct Item: Decodable, Sendable {
            let callsign: String
            let utcTime: Int64
        }

        let type: String
        let subType: String
        let data: [Item]
    }

    private let decoder = JSONDecoder()

    func decodeEvent(_ data: Data) throws -> FmoLocalEvent? {
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw FmoDeviceError.protocolViolation
        }

        guard header.type == "qso" else { return nil }

        do {
            switch header.subType {
            case "callsign":
                let envelope = try decoder.decode(SpeakingEnvelope.self, from: data)
                let callsign = sanitizedOptional(envelope.data.callsign, maximumLength: 32)
                let grid = sanitizedOptional(envelope.data.grid, maximumLength: 16)
                guard !envelope.data.isSpeaking || callsign != nil else {
                    throw FmoDeviceError.protocolViolation
                }
                return .speaking(
                    FmoSpeakingState(
                        callsign: callsign,
                        grid: grid,
                        isSpeaking: envelope.data.isSpeaking,
                        sequence: envelope.seq,
                        deviceUptimeMilliseconds: envelope.ts
                    )
                )

            case "history":
                let envelope = try decoder.decode(HistoryEnvelope.self, from: data)
                guard envelope.data.count <= 20 else { throw FmoDeviceError.protocolViolation }
                let values = try envelope.data.map { item in
                    guard let callsign = sanitizedOptional(item.callsign, maximumLength: 32),
                          item.utcTime >= 0 else {
                        throw FmoDeviceError.protocolViolation
                    }
                    return FmoRecentLocalActivity(
                        callsign: callsign,
                        occurredAt: Date(timeIntervalSince1970: TimeInterval(item.utcTime))
                    )
                }
                return .history(values)

            default:
                return nil
            }
        } catch let error as FmoDeviceError {
            throw error
        } catch {
            throw FmoDeviceError.protocolViolation
        }
    }

    private func sanitizedOptional(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else { return nil }
        return trimmed
    }
}
