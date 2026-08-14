import Foundation
import Testing
@testable import FMOc

struct FmoStationControlWebSocketClientTests {
    @Test
    func loadsBothDeviceListsAndVerifiesACompletedSwitch() async throws {
        let responses = [
            Data(#"{"type":"station","subType":"getListResponse","data":{"list":[{"uid":1,"name":"A"},{"uid":2,"name":"B"}],"count":2},"code":0}"#.utf8),
            Data(#"{"type":"station","subType":"getListResponse","data":{"list":[{"uid":3,"name":"C"}],"count":1},"code":0}"#.utf8),
            Data(#"{"type":"station","subType":"getPinnedListResponse","data":{"list":[{"uid":2,"name":"B"}],"count":1},"code":0}"#.utf8),
            Data(#"{"type":"station","subType":"setCurrentResponse","data":{"result":0},"code":0}"#.utf8),
            Data(#"{"type":"station","subType":"getCurrentResponse","data":{"uid":2,"name":"B"},"code":0}"#.utf8),
        ]
        let transport = StationControlFakeTransport(responses: responses)
        let client = FmoStationControlWebSocketClient(
            transport: transport,
            policy: .init(
                responseTimeout: .seconds(1),
                verificationDelay: .zero,
                pageSize: 2,
                maximumServerCount: 16,
                maximumResponseBytes: 4_096
            )
        )
        try await client.connect(to: FmoDeviceEndpoint(host: "192.0.2.10", source: .manual))

        let updates = StationCatalogUpdateRecorder()
        let catalog = try await client.getServerCatalog { catalog in
            await updates.append(catalog)
        }
        #expect(catalog.all.map(\.uid) == [1, 2, 3])
        #expect(catalog.pinned.map(\.uid) == [2])
        let snapshots = await updates.snapshots
        #expect(snapshots.map { $0.all.map(\.uid) } == [[1, 2], [1, 2, 3], [1, 2, 3]])
        #expect(snapshots.map { $0.pinned.map(\.uid) } == [[], [], [2]])
        #expect(try await client.switchCurrentServer(toUID: 2) == FmoCurrentServer(uid: 2, name: "B"))

        let messages = await transport.sentMessages().map { String(decoding: $0, as: UTF8.self) }
        #expect(messages.map { $0.contains("getListRange") } == [true, true, false, false, false])
        #expect(messages[2].contains("getPinnedList"))
        #expect(messages[3].contains("setCurrent"))
        #expect(messages[4].contains("getCurrent"))
    }

    @Test
    func rejectsAnAcknowledgedSwitchWhenReadbackDoesNotMatch() async throws {
        let transport = StationControlFakeTransport(responses: [
            Data(#"{"type":"station","subType":"setCurrentResponse","data":{"result":0},"code":0}"#.utf8),
            Data(#"{"type":"station","subType":"getCurrentResponse","data":{"uid":1,"name":"A"},"code":0}"#.utf8),
        ])
        let client = FmoStationControlWebSocketClient(
            transport: transport,
            policy: .init(
                responseTimeout: .seconds(1),
                verificationDelay: .zero,
                pageSize: 8,
                maximumServerCount: 16,
                maximumResponseBytes: 4_096
            )
        )
        try await client.connect(to: FmoDeviceEndpoint(host: "192.0.2.10", source: .manual))

        await #expect(throws: FmoDeviceError.unsupportedResponse) {
            try await client.switchCurrentServer(toUID: 2)
        }
    }
}

private actor StationCatalogUpdateRecorder {
    private(set) var snapshots: [FmoDeviceServerCatalog] = []

    func append(_ catalog: FmoDeviceServerCatalog) {
        snapshots.append(catalog)
    }
}

private actor StationControlFakeTransport: FmoWebSocketTransport {
    private var responses: [Data]
    private var messages: [Data] = []
    private var isConnected = false

    init(responses: [Data]) { self.responses = responses }
    func connect(to url: URL) { isConnected = true }
    func send(_ data: Data) throws {
        guard isConnected else { throw FmoDeviceError.disconnected }
        messages.append(data)
    }
    func receive() throws -> Data {
        guard isConnected, !responses.isEmpty else { throw FmoDeviceError.disconnected }
        return responses.removeFirst()
    }
    func disconnect() { isConnected = false }
    func sentMessages() -> [Data] { messages }
}
