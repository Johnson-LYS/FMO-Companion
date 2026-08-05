import Foundation
import Testing
@testable import FMOc

struct FmoLocalEventWebSocketClientTests {
    @Test
    func connectsOnlyToEventsAndRejectsOversizedFrames() async throws {
        let transport = LocalEventFakeTransport(response: Data(repeating: 0x41, count: 65))
        let client = FmoLocalEventWebSocketClient(
            transport: transport,
            policy: .init(maximumEventBytes: 64)
        )
        let endpoint = try FmoDeviceEndpoint(host: "192.0.2.10", port: 8080, source: .manual)
        let stream = await client.events(from: endpoint)

        do {
            for try await _ in stream {
                Issue.record("超限事件不应进入流")
            }
            Issue.record("超限事件应终止事件流")
        } catch let error as FmoDeviceError {
            #expect(error == .protocolViolation)
        }

        #expect(await transport.connectedURL()?.absoluteString == "ws://192.0.2.10:8080/events")
    }
}

private actor LocalEventFakeTransport: FmoWebSocketTransport {
    private let response: Data
    private var url: URL?
    private var hasReturnedResponse = false

    init(response: Data) {
        self.response = response
    }

    func connect(to url: URL) { self.url = url }
    func send(_ data: Data) {}

    func receive() throws -> Data {
        guard !hasReturnedResponse else { throw FmoDeviceError.disconnected }
        hasReturnedResponse = true
        return response
    }

    func disconnect() {}
    func connectedURL() -> URL? { url }
}
