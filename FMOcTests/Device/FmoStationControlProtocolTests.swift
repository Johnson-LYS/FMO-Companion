import Foundation
import Testing
@testable import FMOc

struct FmoStationControlProtocolTests {
    private let codec = FmoStationControlProtocol()

    @Test
    func encodesOnlyTheStationCatalogAndSwitchAllowlist() throws {
        let requests: [(FmoStationControlProtocol.Command, String)] = [
            (.allServers(start: 0, count: 8), "getListRange"),
            (.pinnedServers(start: 0, count: 8), "getPinnedList"),
            (.currentServer, "getCurrent"),
            (.setCurrentServer(uid: 42), "setCurrent"),
        ]

        for (command, subtype) in requests {
            let data = try codec.makeRequest(for: command)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["type"] as? String == "station")
            #expect(object["subType"] as? String == subtype)
            let text = String(decoding: data, as: UTF8.self)
            #expect(!text.contains("Passcode"))
            #expect(!text.contains("next"))
            #expect(!text.contains("prev"))
        }
    }

    @Test
    func decodesSanitizedListsCurrentServerAndSwitchAcknowledgement() throws {
        let list = Data(#"{"type":"station","subType":"getListResponse","data":{"list":[{"uid":42,"name":"服务器 A"},{"uid":84,"name":"服务器 B","private":"ignored"}],"count":2},"code":0}"#.utf8)
        let current = Data(#"{"type":"station","subType":"getCurrentResponse","data":{"uid":42,"name":"服务器 A"},"code":0}"#.utf8)
        let accepted = Data(#"{"type":"station","subType":"setCurrentResponse","data":{"result":0},"code":0}"#.utf8)

        #expect(
            try codec.decodeResponse(list, for: .allServers(start: 0, count: 8))
                == .servers([
                    FmoDeviceServer(uid: 42, name: "服务器 A"),
                    FmoDeviceServer(uid: 84, name: "服务器 B"),
                ], count: 2)
        )
        #expect(
            try codec.decodeResponse(current, for: .currentServer)
                == .currentServer(FmoCurrentServer(uid: 42, name: "服务器 A"))
        )
        #expect(
            try codec.decodeResponse(accepted, for: .setCurrentServer(uid: 42))
                == .currentServerAccepted
        )
    }

    @Test
    func rejectsMalformedOrUnexpectedResponses() {
        let wrongCount = Data(#"{"type":"station","subType":"getListResponse","data":{"list":[{"uid":42,"name":"服务器 A"}],"count":2},"code":0}"#.utf8)
        let duplicate = Data(#"{"type":"station","subType":"getPinnedListResponse","data":{"list":[{"uid":42,"name":"服务器 A"},{"uid":42,"name":"服务器 A"}],"count":2},"code":0}"#.utf8)
        let rejected = Data(#"{"type":"station","subType":"setCurrentResponse","data":{"result":7},"code":0}"#.utf8)

        #expect(throws: FmoDeviceError.protocolViolation) {
            try codec.decodeResponse(wrongCount, for: .allServers(start: 0, count: 8))
        }
        #expect(throws: FmoDeviceError.protocolViolation) {
            try codec.decodeResponse(duplicate, for: .pinnedServers(start: 0, count: 8))
        }
        #expect(throws: FmoDeviceError.deviceRejected(code: 7)) {
            try codec.decodeResponse(rejected, for: .setCurrentServer(uid: 42))
        }
    }
}
