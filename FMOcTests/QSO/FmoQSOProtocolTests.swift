import Foundation
import Testing
@testable import FMOc

struct FmoQSOProtocolTests {
    private let codec = FmoQSOProtocol()

    @Test
    func encodesOnlyTypedReadOnlyListAndDetailRoutes() throws {
        let list = try json(try codec.makeRequest(for: .list(page: 2, pageSize: 100)))
        #expect(list.keys.sorted() == ["data", "subType", "type"])
        #expect(list["type"] as? String == "qso")
        #expect(list["subType"] as? String == "getList")
        let listData = try #require(list["data"] as? [String: Any])
        #expect(listData["page"] as? Int == 2)
        #expect(listData["pageSize"] as? Int == 100)

        let detailData = try json(try codec.makeRequest(for: .detail(logID: 42)))
        #expect(detailData["subType"] as? String == "getDetail")
        #expect((detailData["data"] as? [String: Any])?["logId"] as? Int == 42)

        let encoded = String(decoding: try codec.makeRequest(for: .detail(logID: 42)), as: UTF8.self)
        #expect(!encoded.contains("clear"))
        #expect(!encoded.contains("backup"))
        #expect(!encoded.contains("sign"))
    }

    @Test
    func decodesSanitizedListAndIgnoresUnknownFields() throws {
        let data = Data(#"{"type":"qso","subType":"getListResponse","code":0,"data":{"count":2,"page":0,"pageSize":100,"list":[{"logId":41,"timestamp":1800000000,"toCallsign":"BH0TST","grid":"OM89AA","private":"ignored"},{"logId":42,"timestamp":1800000060,"toCallsign":"BG0TST","grid":null}]}}"#.utf8)
        guard case let .list(page) = try codec.decodeResponse(data, for: .list(page: 0, pageSize: 100)) else {
            Issue.record("Expected list response")
            return
        }
        #expect(page.totalCount == 2)
        #expect(page.summaries.map(\.logID) == [41, 42])
        #expect(page.summaries.first?.toGrid == "OM89AA")
    }

    @Test
    func decodesDetailFieldsWithoutExposingUnknownDeviceData() throws {
        let data = Data(#"{"type":"qso","subType":"getDetailResponse","code":0,"data":{"log":{"logId":42,"timestamp":1800000060,"fromCallsign":"BG0AAA-10","toCallsign":"BH0BBB","fromGrid":"OM89AA","toGrid":"PM01AB","freqHz":1458000,"mode":"FM","relayName":"示例中继","relayAdmin":"BG0CCC","toComment":"73","secret":"ignored"}}}"#.utf8)
        guard case let .detail(detail) = try codec.decodeResponse(data, for: .detail(logID: 42)) else {
            Issue.record("Expected detail response")
            return
        }
        #expect(detail.fromCallsign == "BG0AAA-10")
        #expect(detail.toGrid == "PM01AB")
        #expect(detail.frequencyRaw == 1_458_000)
        #expect(detail.relayName == "示例中继")
    }

    @Test
    func rejectsMismatchedRoutesDuplicateIDsAndMalformedFields() throws {
        let wrongRoute = Data(#"{"type":"qso","subType":"clearAllResponse","code":0,"data":{}}"#.utf8)
        #expect(throws: FmoDeviceError.protocolViolation) {
            try codec.decodeResponse(wrongRoute, for: .detail(logID: 42))
        }

        let duplicate = Data(#"{"type":"qso","subType":"getListResponse","code":0,"data":{"count":2,"page":0,"pageSize":100,"list":[{"logId":42,"timestamp":1800000000,"toCallsign":"BG0AAA","grid":"OM89AA"},{"logId":42,"timestamp":1800000060,"toCallsign":"BG0BBB","grid":"PM01AB"}]}}"#.utf8)
        #expect(throws: FmoDeviceError.protocolViolation) {
            try codec.decodeResponse(duplicate, for: .list(page: 0, pageSize: 100))
        }

        let invalidGrid = Data(#"{"type":"qso","subType":"getListResponse","code":0,"data":{"count":1,"page":0,"pageSize":100,"list":[{"logId":42,"timestamp":1800000000,"toCallsign":"BG0AAA","grid":"ZZ99ZZ"}]}}"#.utf8)
        #expect(throws: FmoDeviceError.protocolViolation) {
            try codec.decodeResponse(invalidGrid, for: .list(page: 0, pageSize: 100))
        }

        let missingLogEnvelope = Data(#"{"type":"qso","subType":"getDetailResponse","code":0,"data":{"logId":42}}"#.utf8)
        #expect(throws: FmoDeviceError.protocolViolation) {
            try codec.decodeResponse(missingLogEnvelope, for: .detail(logID: 42))
        }
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
