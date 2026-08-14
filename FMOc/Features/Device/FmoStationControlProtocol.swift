import Foundation

nonisolated struct FmoDeviceServer: Equatable, Identifiable, Sendable {
    let uid: Int64
    let name: String

    var id: Int64 { uid }
}

nonisolated struct FmoDeviceServerCatalog: Equatable, Sendable {
    let all: [FmoDeviceServer]
    let pinned: [FmoDeviceServer]
}

nonisolated struct FmoStationControlProtocol: Sendable {
    enum Command: Equatable, Sendable {
        case allServers(start: Int, count: Int)
        case pinnedServers(start: Int, count: Int)
        case currentServer
        case setCurrentServer(uid: Int64)
    }

    enum Response: Equatable, Sendable {
        case servers([FmoDeviceServer], count: Int)
        case currentServer(FmoCurrentServer)
        case currentServerAccepted
    }

    private struct EmptyData: Codable, Sendable {}

    private struct RangeData: Encodable, Sendable {
        let start: Int
        let count: Int
    }

    private struct SetCurrentData: Encodable, Sendable {
        let uid: Int64
    }

    private struct Request<Value: Encodable & Sendable>: Encodable, Sendable {
        let type: String
        let subType: String
        let data: Value
    }

    private struct Header: Decodable, Sendable {
        let type: String
        let subType: String
        let code: Int
    }

    private struct Envelope<Value: Decodable & Sendable>: Decodable, Sendable {
        let type: String
        let subType: String
        let data: Value
        let code: Int
    }

    private struct ServerData: Decodable, Sendable {
        let uid: Int64
        let name: String
    }

    private struct ListData: Decodable, Sendable {
        let list: [ServerData]
        let count: Int
    }

    private struct CurrentData: Decodable, Sendable {
        let uid: Int64
        let name: String
    }

    private struct ResultData: Decodable, Sendable {
        let result: Int
    }

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
        decoder = JSONDecoder()
    }

    func makeRequest(for command: Command) throws -> Data {
        switch command {
        case let .allServers(start, count):
            try validateRange(start: start, count: count)
            return try encoder.encode(
                Request(type: "station", subType: "getListRange", data: RangeData(start: start, count: count))
            )
        case let .pinnedServers(start, count):
            try validateRange(start: start, count: count)
            return try encoder.encode(
                Request(type: "station", subType: "getPinnedList", data: RangeData(start: start, count: count))
            )
        case .currentServer:
            return try encoder.encode(Request(type: "station", subType: "getCurrent", data: EmptyData()))
        case .setCurrentServer(let uid):
            guard uid > 0 else { throw FmoDeviceError.protocolViolation }
            return try encoder.encode(Request(type: "station", subType: "setCurrent", data: SetCurrentData(uid: uid)))
        }
    }

    func decodeResponse(_ data: Data, for command: Command) throws -> Response {
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw FmoDeviceError.protocolViolation
        }

        guard header.code == 0 else { throw FmoDeviceError.deviceRejected(code: header.code) }
        guard header.type == "station" else { throw FmoDeviceError.protocolViolation }
        guard header.subType == responseSubtype(for: command) else {
            throw FmoDeviceError.protocolViolation
        }

        do {
            switch command {
            case .allServers, .pinnedServers:
                let payload = try decoder.decode(Envelope<ListData>.self, from: data).data
                guard payload.count == payload.list.count else { throw FmoDeviceError.protocolViolation }
                let servers = try payload.list.map(validatedServer)
                guard Set(servers.map(\.uid)).count == servers.count else {
                    throw FmoDeviceError.protocolViolation
                }
                return .servers(servers, count: payload.count)
            case .currentServer:
                let value = try decoder.decode(Envelope<CurrentData>.self, from: data).data
                let server = try validatedServer(ServerData(uid: value.uid, name: value.name))
                return .currentServer(FmoCurrentServer(uid: server.uid, name: server.name))
            case .setCurrentServer:
                let result = try decoder.decode(Envelope<ResultData>.self, from: data).data.result
                guard result == 0 else { throw FmoDeviceError.deviceRejected(code: result) }
                return .currentServerAccepted
            }
        } catch let error as FmoDeviceError {
            throw error
        } catch {
            throw FmoDeviceError.protocolViolation
        }
    }

    private func responseSubtype(for command: Command) -> String {
        switch command {
        case .allServers: "getListResponse"
        case .pinnedServers: "getPinnedListResponse"
        case .currentServer: "getCurrentResponse"
        case .setCurrentServer: "setCurrentResponse"
        }
    }

    private func validateRange(start: Int, count: Int) throws {
        guard start >= 0, start <= 4_096, count > 0, count <= 64 else {
            throw FmoDeviceError.protocolViolation
        }
    }

    private func validatedServer(_ value: ServerData) throws -> FmoDeviceServer {
        let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.uid > 0, !name.isEmpty, name.count <= 128 else {
            throw FmoDeviceError.protocolViolation
        }
        return FmoDeviceServer(uid: value.uid, name: name)
    }
}
