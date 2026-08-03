import Foundation
import Testing
@testable import FMOc

struct FmoGeoWebSocketClientTests {
    @Test
    func readsAndWritesCoordinatesInOrder() async throws {
        let transport = FakeWebSocketTransport(responses: [
            Data(#"{"type":"config","subType":"getCordinateResponse","data":{"latitude":30,"longitude":120},"code":0}"#.utf8),
            Data(#"{"type":"config","subType":"setCordinateResponse","data":{"result":0},"code":0}"#.utf8),
        ])
        let client = FmoGeoWebSocketClient(transport: transport)
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .manual)
        try await client.connect(to: endpoint)

        #expect(try await client.getCoordinate() == GeoCoordinate(latitude: 30, longitude: 120))
        try await client.setCoordinate(GeoCoordinate(latitude: 31, longitude: 121))

        let messages = await transport.sentMessages()
        #expect(messages.count == 2)
        #expect(String(decoding: messages[0], as: UTF8.self).contains("getCordinate"))
        #expect(String(decoding: messages[1], as: UTF8.self).contains("setCordinate"))
    }

    @Test
    func timesOutAndCancelsPendingReceive() async throws {
        let transport = FakeWebSocketTransport(responses: [], suspendWhenEmpty: true)
        let client = FmoGeoWebSocketClient(
            transport: transport,
            policy: .init(responseTimeout: .milliseconds(20))
        )
        try await client.connect(to: FmoDeviceEndpoint(host: "fmo.local", source: .manual))

        await #expect(throws: FmoDeviceError.responseTimedOut) {
            try await client.getCoordinate()
        }
    }
}

private actor FakeWebSocketTransport: FmoWebSocketTransport {
    private var responses: [Data]
    private var messages: [Data] = []
    private let suspendWhenEmpty: Bool
    private var isConnected = false

    init(responses: [Data], suspendWhenEmpty: Bool = false) {
        self.responses = responses
        self.suspendWhenEmpty = suspendWhenEmpty
    }

    func connect(to url: URL) {
        isConnected = true
    }

    func send(_ data: Data) throws {
        guard isConnected else { throw FmoDeviceError.disconnected }
        messages.append(data)
    }

    func receive() async throws -> Data {
        guard isConnected else { throw FmoDeviceError.disconnected }
        if responses.isEmpty, suspendWhenEmpty {
            try await Task.sleep(for: .seconds(10))
        }
        guard !responses.isEmpty else { throw FmoDeviceError.disconnected }
        return responses.removeFirst()
    }

    func disconnect() {
        isConnected = false
    }

    func sentMessages() -> [Data] { messages }
}
