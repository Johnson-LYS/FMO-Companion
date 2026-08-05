import Foundation
import Testing
@testable import FMOc

struct FmoLocalStatusWebSocketClientTests {
    @Test
    func performsOnlyTypedReadRequestsInSerialOrder() async throws {
        let responses = [
            Data(#"{"type":"user","subType":"getInfoResponse","data":{"callsign":"BG0TST"},"code":0}"#.utf8),
            Data(#"{"type":"station","subType":"getCurrentResponse","data":{"uid":42,"name":"测试服务器"},"code":0}"#.utf8),
            Data(#"{"type":"config","subType":"getServerFilterResponse","data":{"serverFilter":4},"code":0}"#.utf8),
            Data(#"{"type":"config","subType":"getUserPhyFreqResponse","data":{"freq":438.5},"code":0}"#.utf8),
            Data(#"{"type":"qso","subType":"getListResponse","data":{"count":18},"code":0}"#.utf8)
        ]
        let transport = LocalStatusFakeTransport(responses: responses)
        let client = FmoLocalStatusWebSocketClient(transport: transport)
        let endpoint = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual)

        try await client.connect(to: endpoint)
        #expect(try await client.getCallsign() == "BG0TST")
        #expect(try await client.getCurrentServer().name == "测试服务器")
        #expect(try await client.getServerFilter() == .kilometers(500))
        #expect(try await client.getWorkingFrequencyMHz() == 438.5)
        #expect(try await client.getQSOLogCount() == 18)

        let messages = await transport.sentMessages().map { String(decoding: $0, as: UTF8.self) }
        #expect(messages.count == 5)
        #expect(messages[0].contains("getInfo"))
        #expect(messages[1].contains("getCurrent"))
        #expect(messages[2].contains("getServerFilter"))
        #expect(messages[3].contains("getUserPhyFreq"))
        #expect(messages[4].contains("getList"))
        #expect(messages.allSatisfy { !$0.contains("Passcode") && !$0.contains("setCurrent") })
    }

    @Test
    func rejectsOversizedResponseAndClosesTheSession() async throws {
        let response = Data(#"{"type":"user","subType":"getInfoResponse","data":{"callsign":"BG0TST"},"code":0}"#.utf8)
        let transport = LocalStatusFakeTransport(responses: [response])
        let client = FmoLocalStatusWebSocketClient(
            transport: transport,
            policy: .init(responseTimeout: .seconds(1), maximumResponseBytes: 32)
        )
        try await client.connect(to: FmoDeviceEndpoint(host: "192.0.2.10", source: .manual))

        await #expect(throws: FmoDeviceError.protocolViolation) {
            try await client.getCallsign()
        }
        await #expect(throws: FmoDeviceError.disconnected) {
            try await client.getCallsign()
        }
    }
}

private actor LocalStatusFakeTransport: FmoWebSocketTransport {
    private var responses: [Data]
    private var messages: [Data] = []
    private var isConnected = false

    init(responses: [Data]) {
        self.responses = responses
    }

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
