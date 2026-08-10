import Foundation

nonisolated struct FmoQSOSummary: Equatable, Sendable {
    let logID: Int64
    let timestamp: Date
    let toCallsign: String
    let toGrid: String?

    var fingerprint: String {
        "\(logID)|\(Int64(timestamp.timeIntervalSince1970))|\(toCallsign)|\(toGrid ?? "")"
    }
}

nonisolated struct FmoQSODetail: Equatable, Sendable {
    let logID: Int64
    let timestamp: Date
    let fromCallsign: String
    let toCallsign: String
    let fromGrid: String?
    let toGrid: String?
    let frequencyRaw: Int64?
    let mode: String?
    let relayName: String?
    let relayAdmin: String?
    let comment: String?
}

nonisolated struct FmoQSOListPage: Equatable, Sendable {
    let totalCount: Int
    let page: Int
    let pageSize: Int
    let summaries: [FmoQSOSummary]
}

nonisolated struct FmoQSOProtocol: Sendable {
    enum Command: Equatable, Sendable {
        case list(page: Int, pageSize: Int)
        case detail(logID: Int64)
    }

    enum Response: Equatable, Sendable {
        case list(FmoQSOListPage)
        case detail(FmoQSODetail)
    }

    private struct Request<DataValue: Encodable & Sendable>: Encodable, Sendable {
        let type = "qso"
        let subType: String
        let data: DataValue
    }

    private struct ListRequest: Encodable, Sendable {
        let page: Int
        let pageSize: Int
    }

    private struct DetailRequest: Encodable, Sendable {
        let logId: Int64
    }

    private struct Header: Decodable, Sendable {
        let type: String
        let subType: String
        let code: Int
    }

    private struct Envelope<Value: Decodable & Sendable>: Decodable, Sendable {
        let data: Value
    }

    private struct ListData: Decodable, Sendable {
        let count: Int
        let page: Int
        let pageSize: Int
        let list: [SummaryData]
    }

    private struct SummaryData: Decodable, Sendable {
        let grid: String?
        let logId: Int64
        let timestamp: Double
        let toCallsign: String
    }

    private struct DetailData: Decodable, Sendable {
        let freqHz: Int64?
        let fromCallsign: String
        let fromGrid: String?
        let logId: Int64
        let mode: String?
        let relayAdmin: String?
        let relayName: String?
        let timestamp: Double
        let toCallsign: String
        let toComment: String?
        let toGrid: String?
    }

    private struct DetailResponseData: Decodable, Sendable {
        let log: DetailData
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
        case let .list(page, pageSize):
            guard page >= 0, (1...100).contains(pageSize) else {
                throw FmoDeviceError.protocolViolation
            }
            return try encoder.encode(
                Request(subType: "getList", data: ListRequest(page: page, pageSize: pageSize))
            )
        case let .detail(logID):
            guard logID > 0 else { throw FmoDeviceError.protocolViolation }
            return try encoder.encode(
                Request(subType: "getDetail", data: DetailRequest(logId: logID))
            )
        }
    }

    func decodeResponse(_ data: Data, for command: Command) throws -> Response {
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw FmoDeviceError.protocolViolation
        }
        guard header.type == "qso", header.subType == expectedResponseSubtype(for: command) else {
            throw FmoDeviceError.protocolViolation
        }
        guard header.code == 0 else { throw FmoDeviceError.deviceRejected(code: header.code) }

        do {
            switch command {
            case let .list(requestedPage, requestedPageSize):
                let value = try decoder.decode(Envelope<ListData>.self, from: data).data
                guard value.count >= 0,
                      value.page == requestedPage,
                      value.pageSize == requestedPageSize,
                      value.list.count <= requestedPageSize else {
                    throw FmoDeviceError.protocolViolation
                }
                var seen = Set<Int64>()
                let summaries = try value.list.map { item in
                    guard seen.insert(item.logId).inserted else {
                        throw FmoDeviceError.protocolViolation
                    }
                    return try summary(from: item)
                }
                return .list(FmoQSOListPage(
                    totalCount: value.count,
                    page: value.page,
                    pageSize: value.pageSize,
                    summaries: summaries
                ))

            case let .detail(requestedLogID):
                let value = try decoder.decode(Envelope<DetailResponseData>.self, from: data).data.log
                guard value.logId == requestedLogID else { throw FmoDeviceError.protocolViolation }
                return .detail(try detail(from: value))
            }
        } catch let error as FmoDeviceError {
            throw error
        } catch {
            throw FmoDeviceError.protocolViolation
        }
    }

    private func expectedResponseSubtype(for command: Command) -> String {
        switch command {
        case .list: "getListResponse"
        case .detail: "getDetailResponse"
        }
    }

    private func summary(from value: SummaryData) throws -> FmoQSOSummary {
        FmoQSOSummary(
            logID: try validatedLogID(value.logId),
            timestamp: try validatedDate(value.timestamp),
            toCallsign: try validatedRequired(value.toCallsign, maximumLength: 32),
            toGrid: try validatedGrid(value.grid)
        )
    }

    private func detail(from value: DetailData) throws -> FmoQSODetail {
        if let frequency = value.freqHz, frequency <= 0 {
            throw FmoDeviceError.protocolViolation
        }
        return FmoQSODetail(
            logID: try validatedLogID(value.logId),
            timestamp: try validatedDate(value.timestamp),
            fromCallsign: try validatedRequired(value.fromCallsign, maximumLength: 32),
            toCallsign: try validatedRequired(value.toCallsign, maximumLength: 32),
            fromGrid: try validatedGrid(value.fromGrid),
            toGrid: try validatedGrid(value.toGrid),
            frequencyRaw: value.freqHz,
            mode: try validatedOptional(value.mode, maximumLength: 32),
            relayName: try validatedOptional(value.relayName, maximumLength: 128),
            relayAdmin: try validatedOptional(value.relayAdmin, maximumLength: 32),
            comment: try validatedOptional(value.toComment, maximumLength: 2_048)
        )
    }

    private func validatedLogID(_ value: Int64) throws -> Int64 {
        guard value > 0 else { throw FmoDeviceError.protocolViolation }
        return value
    }

    private func validatedDate(_ value: Double) throws -> Date {
        guard value.isFinite, value > 0 else { throw FmoDeviceError.protocolViolation }
        return Date(timeIntervalSince1970: value)
    }

    private func validatedRequired(_ value: String, maximumLength: Int) throws -> String {
        guard let result = try validatedOptional(value, maximumLength: maximumLength) else {
            throw FmoDeviceError.protocolViolation
        }
        return result
    }

    private func validatedOptional(_ value: String?, maximumLength: Int) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard trimmed.count <= maximumLength else { throw FmoDeviceError.protocolViolation }
        return trimmed
    }

    private func validatedGrid(_ value: String?) throws -> String? {
        guard let grid = try validatedOptional(value, maximumLength: 8)?.uppercased() else {
            return nil
        }
        guard MaidenheadGrid.isValid(grid) else { throw FmoDeviceError.protocolViolation }
        return grid
    }
}
