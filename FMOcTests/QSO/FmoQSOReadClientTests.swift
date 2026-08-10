import Foundation
import Testing
@testable import FMOc

struct FmoQSOReadClientTests {
    @Test
    func sendsOnlyListAndDetailOverTheSelectedDeviceWebSocket() async throws {
        let responses = [
            Data(#"{"type":"qso","subType":"getListResponse","code":0,"data":{"count":1,"page":0,"pageSize":100,"list":[{"logId":42,"timestamp":1800000000,"toCallsign":"BG0AAA","grid":"OM89AA"}]}}"#.utf8),
            Data(#"{"type":"qso","subType":"getDetailResponse","code":0,"data":{"log":{"logId":42,"timestamp":1800000000,"fromCallsign":"BG0TST","toCallsign":"BG0AAA","fromGrid":"OM89AA","toGrid":"PM01AB","freqHz":1458000,"mode":"FM","relayName":"示例中继","relayAdmin":null,"toComment":null}}}"#.utf8)
        ]
        let transport = QSOFakeTransport(responses: responses)
        let client = FmoQSOReadClient(transport: transport)
        let endpoint = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual)

        try await client.connect(to: endpoint)
        #expect(try await client.list(page: 0, pageSize: 100).totalCount == 1)
        #expect(try await client.detail(logID: 42).toCallsign == "BG0AAA")

        let state = await transport.state()
        #expect(state.url?.path == "/ws")
        #expect(state.messages.count == 2)
        #expect(state.messages[0].contains("getList"))
        #expect(state.messages[1].contains("getDetail"))
    }

    @Test
    func oversizedFrameClosesSessionAndPreservesFailClosedBehavior() async throws {
        let transport = QSOFakeTransport(responses: [Data(repeating: 1, count: 64)])
        let client = FmoQSOReadClient(
            transport: transport,
            policy: .init(responseTimeout: .seconds(1), maximumResponseBytes: 32)
        )
        try await client.connect(to: FmoDeviceEndpoint(host: "192.0.2.10", source: .manual))
        await #expect(throws: FmoDeviceError.protocolViolation) {
            try await client.list(page: 0, pageSize: 100)
        }
        await #expect(throws: FmoDeviceError.disconnected) {
            try await client.list(page: 0, pageSize: 100)
        }
    }
}

private actor QSOFakeTransport: FmoWebSocketTransport {
    struct State: Sendable {
        let url: URL?
        let messages: [String]
    }

    private var responses: [Data]
    private var url: URL?
    private var messages: [String] = []

    init(responses: [Data]) { self.responses = responses }
    func connect(to url: URL) { self.url = url }
    func send(_ data: Data) throws {
        guard url != nil else { throw FmoDeviceError.disconnected }
        messages.append(String(decoding: data, as: UTF8.self))
    }
    func receive() throws -> Data {
        guard url != nil, !responses.isEmpty else { throw FmoDeviceError.disconnected }
        return responses.removeFirst()
    }
    func disconnect() { url = nil }
    func state() -> State { State(url: url, messages: messages) }
}
