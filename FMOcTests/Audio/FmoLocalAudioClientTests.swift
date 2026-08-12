import Foundation
import Testing
@testable import FMOc

struct FmoLocalAudioClientTests {
    @Test
    func connectsToAudioIgnoresKeepaliveAndYieldsPCM() async throws {
        let transport = AudioFakeTransport(messages: [
            .text("p"),
            .binary(Data(count: FmoPCMFrame.byteCount)),
        ])
        let client = FmoLocalAudioClient(transport: transport)
        let endpoint = try FmoDeviceEndpoint(host: "192.0.2.10", port: 8080, source: .manual)
        let stream = await client.frames(from: endpoint)
        var iterator = stream.makeAsyncIterator()

        let frame = try #require(try await iterator.next())

        #expect(frame.samples.count == FmoPCMFrame.sampleCount)
        #expect(await transport.connectedURL()?.absoluteString == "ws://192.0.2.10:8080/audio")
        await client.disconnect()
    }

    @Test
    func unknownTextFailsClosed() async throws {
        let transport = AudioFakeTransport(messages: [.text("unknown")])
        let client = FmoLocalAudioClient(transport: transport)
        let endpoint = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual)
        let stream = await client.frames(from: endpoint)

        do {
            for try await _ in stream {
                Issue.record("未知文本不应产生 PCM")
            }
            Issue.record("未知文本应关闭音频流")
        } catch let error as FmoLocalAudioError {
            #expect(error == .unexpectedText)
        }
    }
}

private actor AudioFakeTransport: FmoAudioWebSocketTransport {
    private var messages: [FmoAudioWebSocketMessage]
    private var url: URL?

    init(messages: [FmoAudioWebSocketMessage]) {
        self.messages = messages
    }

    func connect(to url: URL) { self.url = url }

    func receive() throws -> FmoAudioWebSocketMessage {
        guard !messages.isEmpty else { throw FmoDeviceError.disconnected }
        return messages.removeFirst()
    }

    func disconnect() {}
    func connectedURL() -> URL? { url }
}
