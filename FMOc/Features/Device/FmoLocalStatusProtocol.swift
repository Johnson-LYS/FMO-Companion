import Foundation

nonisolated struct FmoCurrentServer: Equatable, Sendable {
    let uid: Int64
    let name: String
}

nonisolated enum FmoServerFilter: Equatable, Sendable {
    case disabled
    case kilometers(Int)
}

nonisolated struct FmoLocalStatusProtocol: Sendable {
    enum Command: CaseIterable, Equatable, Sendable {
        case callsign
        case currentServer
        case serverFilter
        case workingFrequency
        case qsoLogCount
    }

    enum Response: Equatable, Sendable {
        case callsign(String)
        case currentServer(FmoCurrentServer)
        case serverFilter(FmoServerFilter)
        case workingFrequencyMHz(Double)
        case qsoLogCount(Int)
    }

    private struct EmptyData: Codable, Sendable {}

    private struct Request<DataValue: Encodable & Sendable>: Encodable, Sendable {
        let type: String
        let subType: String
        let data: DataValue
    }

    private struct ListRequestData: Encodable, Sendable {
        let page = 0
        let pageSize = 20
    }

    private struct ResponseHeader: Decodable, Sendable {
        let type: String
        let subType: String
        let code: Int
    }

    private struct ResponseEnvelope<DataValue: Decodable & Sendable>: Decodable, Sendable {
        let type: String
        let subType: String
        let data: DataValue
        let code: Int
    }

    private struct UserInfoData: Decodable, Sendable {
        let callsign: String
    }

    private struct CurrentServerData: Decodable, Sendable {
        let uid: Int64
        let name: String
    }

    private struct ServerFilterData: Decodable, Sendable {
        let serverFilter: Int
    }

    private struct WorkingFrequencyData: Decodable, Sendable {
        let freq: Double
    }

    private struct QSOListData: Decodable, Sendable {
        let count: Int
    }

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func makeRequest(for command: Command) throws -> Data {
        switch command {
        case .callsign:
            try makeEmptyRequest(type: "user", subType: "getInfo")
        case .currentServer:
            try makeEmptyRequest(type: "station", subType: "getCurrent")
        case .serverFilter:
            try makeEmptyRequest(type: "config", subType: "getServerFilter")
        case .workingFrequency:
            try makeEmptyRequest(type: "config", subType: "getUserPhyFreq")
        case .qsoLogCount:
            try encoder.encode(Request(type: "qso", subType: "getList", data: ListRequestData()))
        }
    }

    func decodeResponse(_ data: Data, for command: Command) throws -> Response {
        let header: ResponseHeader
        do {
            header = try decoder.decode(ResponseHeader.self, from: data)
        } catch {
            throw FmoDeviceError.protocolViolation
        }

        guard header.code == 0 else { throw FmoDeviceError.deviceRejected(code: header.code) }
        let expected = route(for: command)
        guard header.type == expected.type, header.subType == expected.responseSubType else {
            throw FmoDeviceError.protocolViolation
        }

        do {
            switch command {
            case .callsign:
                let value = try decode(UserInfoData.self, from: data).callsign
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, value.count <= 32 else { throw FmoDeviceError.protocolViolation }
                return .callsign(value)

            case .currentServer:
                let value = try decode(CurrentServerData.self, from: data)
                let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name.count <= 128 else { throw FmoDeviceError.protocolViolation }
                return .currentServer(FmoCurrentServer(uid: value.uid, name: name))

            case .serverFilter:
                let rawValue = try decode(ServerFilterData.self, from: data).serverFilter
                return .serverFilter(try Self.serverFilter(from: rawValue))

            case .workingFrequency:
                let value = try decode(WorkingFrequencyData.self, from: data).freq
                guard value.isFinite, value > 0, value < 10_000 else {
                    throw FmoDeviceError.protocolViolation
                }
                return .workingFrequencyMHz(value)

            case .qsoLogCount:
                let value = try decode(QSOListData.self, from: data).count
                guard value >= 0 else { throw FmoDeviceError.protocolViolation }
                return .qsoLogCount(value)
            }
        } catch let error as FmoDeviceError {
            throw error
        } catch {
            throw FmoDeviceError.protocolViolation
        }
    }

    private func makeEmptyRequest(type: String, subType: String) throws -> Data {
        try encoder.encode(Request(type: type, subType: subType, data: EmptyData()))
    }

    private func decode<Value: Decodable & Sendable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        try decoder.decode(ResponseEnvelope<Value>.self, from: data).data
    }

    private func route(for command: Command) -> (type: String, responseSubType: String) {
        switch command {
        case .callsign: ("user", "getInfoResponse")
        case .currentServer: ("station", "getCurrentResponse")
        case .serverFilter: ("config", "getServerFilterResponse")
        case .workingFrequency: ("config", "getUserPhyFreqResponse")
        case .qsoLogCount: ("qso", "getListResponse")
        }
    }

    private static func serverFilter(from rawValue: Int) throws -> FmoServerFilter {
        switch rawValue {
        case 0: .disabled
        case 1: .kilometers(50)
        case 2: .kilometers(100)
        case 3: .kilometers(200)
        case 4: .kilometers(500)
        case 5: .kilometers(1_000)
        case 6: .kilometers(2_000)
        case 7: .kilometers(5_000)
        default: throw FmoDeviceError.protocolViolation
        }
    }
}
