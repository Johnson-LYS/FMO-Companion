import Foundation
import Testing
@testable import FMOc

struct FmoLocalStatusProtocolTests {
    private let codec = FmoLocalStatusProtocol()

    @Test
    func encodesOnlyTheFiveReadOnlyAllowlistedRequests() throws {
        let expected: [FmoLocalStatusProtocol.Command: (String, String)] = [
            .callsign: ("user", "getInfo"),
            .currentServer: ("station", "getCurrent"),
            .serverFilter: ("config", "getServerFilter"),
            .workingFrequency: ("config", "getUserPhyFreq"),
            .qsoLogCount: ("qso", "getList")
        ]

        for command in FmoLocalStatusProtocol.Command.allCases {
            let request = try codec.makeRequest(for: command)
            let object = try #require(JSONSerialization.jsonObject(with: request) as? [String: Any])
            let route = try #require(expected[command])

            #expect(object.keys.sorted() == ["data", "subType", "type"])
            #expect(object["type"] as? String == route.0)
            #expect(object["subType"] as? String == route.1)
            #expect(!String(decoding: request, as: UTF8.self).contains("Passcode"))
        }

        let listRequest = try codec.makeRequest(for: .qsoLogCount)
        let object = try #require(JSONSerialization.jsonObject(with: listRequest) as? [String: Any])
        let data = try #require(object["data"] as? [String: Any])
        #expect(data["page"] as? Int == 0)
        #expect(data["pageSize"] as? Int == 20)
    }

    @Test
    func decodesSanitizedDashboardFieldsAndIgnoresUnknownResponseFields() throws {
        let callsign = Data(#"{"type":"user","subType":"getInfoResponse","data":{"callsign":"BG0TST","passcode":"NOT_A_SECRET","wlanIP":"192.0.2.1"},"code":0}"#.utf8)
        let server = Data(#"{"type":"station","subType":"getCurrentResponse","data":{"uid":42,"name":"测试服务器"},"code":0}"#.utf8)
        let filter = Data(#"{"type":"config","subType":"getServerFilterResponse","data":{"serverFilter":4},"code":0}"#.utf8)
        let frequency = Data(#"{"type":"config","subType":"getUserPhyFreqResponse","data":{"freq":438.5},"code":0}"#.utf8)
        let qso = Data(#"{"type":"qso","subType":"getListResponse","data":{"count":18,"page":0,"pageSize":20,"list":[]},"code":0}"#.utf8)

        #expect(try codec.decodeResponse(callsign, for: .callsign) == .callsign("BG0TST"))
        #expect(try codec.decodeResponse(server, for: .currentServer) == .currentServer(FmoCurrentServer(uid: 42, name: "测试服务器")))
        #expect(try codec.decodeResponse(filter, for: .serverFilter) == .serverFilter(.kilometers(500)))
        #expect(try codec.decodeResponse(frequency, for: .workingFrequency) == .workingFrequencyMHz(438.5))
        #expect(try codec.decodeResponse(qso, for: .qsoLogCount) == .qsoLogCount(18))
    }

    @Test
    func mapsEveryKnownFilterValueAndRejectsUnknownValues() throws {
        let expected: [FmoServerFilter] = [
            .disabled,
            .kilometers(50),
            .kilometers(100),
            .kilometers(200),
            .kilometers(500),
            .kilometers(1_000),
            .kilometers(2_000),
            .kilometers(5_000)
        ]

        for (rawValue, value) in expected.enumerated() {
            let fixture = Data(#"{"type":"config","subType":"getServerFilterResponse","data":{"serverFilter":\#(rawValue)},"code":0}"#.utf8)
            #expect(try codec.decodeResponse(fixture, for: .serverFilter) == .serverFilter(value))
        }

        let unknown = Data(#"{"type":"config","subType":"getServerFilterResponse","data":{"serverFilter":8},"code":0}"#.utf8)
        #expect(throws: FmoDeviceError.protocolViolation) {
            try codec.decodeResponse(unknown, for: .serverFilter)
        }
    }

    @Test
    func rejectsMismatchedResponseRouteAndDeviceFailure() {
        let wrongRoute = Data(#"{"type":"config","subType":"getPasscodeResponse","data":{"passcode":"NOT_A_SECRET"},"code":0}"#.utf8)
        let rejected = Data(#"{"type":"user","subType":"getInfoResponse","data":{},"code":7}"#.utf8)

        #expect(throws: FmoDeviceError.protocolViolation) {
            try codec.decodeResponse(wrongRoute, for: .callsign)
        }
        #expect(throws: FmoDeviceError.deviceRejected(code: 7)) {
            try codec.decodeResponse(rejected, for: .callsign)
        }
    }
}
