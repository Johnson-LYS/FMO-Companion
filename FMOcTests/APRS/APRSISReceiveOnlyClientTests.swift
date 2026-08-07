import Foundation
import Testing
@testable import FMOc

struct APRSISReceiveOnlyClientTests {
    @Test
    func waitsForGreetingThenSendsOneFixedLoginAndYieldsFrame() async throws {
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "ZZ0TST", ssid: 10)
        let transport = FakeAPRSISByteTransport(
            chunks: [
                Data("# aprsc 2.1.19\r\n".utf8),
                Data(
                    (
                        "# logresp ZZ0TST-10 unverified, server T2TEST\r\n"
                            + validActivityLine
                            + "\r\n"
                    ).utf8
                ),
            ]
        )
        let sut = APRSISReceiveOnlyClient(
            transport: transport,
            aprsISProtocol: try APRSISProtocol(
                softwareName: "FMOCompanion",
                softwareVersion: "0.4"
            )
        )

        let stream = await sut.events(identity: identity, endpoint: .asia)
        var iterator = stream.makeAsyncIterator()
        let readyEvent = try await iterator.next()
        let event = try await iterator.next()
        await sut.disconnect()

        #expect(readyEvent == .sessionReady(serverCallsign: "T2TEST"))
        guard let event, case .frame(.position) = event else {
            Issue.record("Expected parsed position frame")
            return
        }
        #expect(
            await transport.sentData()
                == [
                    Data(
                        "user ZZ0TST-10 pass -1 vers FMOCompanion 0.4 filter u/APFMO4\r\n"
                            .utf8
                    ),
                ]
        )
        #expect(await transport.connectedEndpoints() == [.asia])
    }

    @Test
    func reportsRejectedPacketWithoutEndingReceiveStream() async throws {
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "ZZ0TST", ssid: 10)
        let transport = FakeAPRSISByteTransport(
            chunks: [
                Data("# aprsc 2.1.19\r\n".utf8),
                Data(
                    (
                        "# logresp ZZ0TST-10 unverified, server T2TEST\r\n"
                            + "not a packet\r\n"
                            + validActivityLine
                            + "\r\n"
                    ).utf8
                ),
            ]
        )
        let sut = APRSISReceiveOnlyClient(
            transport: transport,
            aprsISProtocol: try APRSISProtocol(
                softwareName: "FMOCompanion",
                softwareVersion: "0.4"
            )
        )

        let stream = await sut.events(identity: identity, endpoint: .asia)
        var iterator = stream.makeAsyncIterator()
        let readyEvent = try await iterator.next()
        let first = try await iterator.next()
        let second = try await iterator.next()
        await sut.disconnect()

        #expect(readyEvent == .sessionReady(serverCallsign: "T2TEST"))
        #expect(first == APRSISInboundEvent.rejected(.invalidTNC2))
        guard let second, case .frame(.position) = second else {
            Issue.record("Expected stream to continue with valid frame")
            return
        }
    }

    private var validActivityLine: String {
        let certificate = base64URL(Data(repeating: 0x01, count: 125))
        let signature = base64URL(Data(repeating: 0x02, count: 64))
        return "ZZ0TST-15>APFMO4,TCPIP*:=0000.00N/00000.00EiFMO-V4,VOCAL,CERT:\(certificate),S123,SIG:\(signature)"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private actor FakeAPRSISByteTransport: APRSISByteTransport {
    private var chunks: [Data]
    private var endpoints: [APRSISEndpoint] = []
    private var sends: [Data] = []
    private var connected = false

    init(chunks: [Data]) {
        self.chunks = chunks
    }

    func connect(to endpoint: APRSISEndpoint) async throws {
        endpoints.append(endpoint)
        connected = true
    }

    func send(_ data: Data) async throws {
        guard connected else { throw APRSISTransportError.disconnected }
        sends.append(data)
    }

    func receive(maximumLength: Int) async throws -> Data {
        guard connected else { throw APRSISTransportError.disconnected }
        guard !chunks.isEmpty else {
            try await Task.sleep(for: .seconds(30))
            throw CancellationError()
        }
        let chunk = chunks.removeFirst()
        #expect(chunk.count <= maximumLength)
        return chunk
    }

    func disconnect() async {
        connected = false
    }

    func sentData() -> [Data] {
        sends
    }

    func connectedEndpoints() -> [APRSISEndpoint] {
        endpoints
    }
}
