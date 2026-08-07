import Foundation

nonisolated enum APRSISMessagingEvent: Equatable, Sendable {
    case sessionReady(serverCallsign: String)
    case message(APRSMessageEnvelope)
    case rejectedPacket
}

nonisolated enum APRSISMessagingClientError: Error, Equatable, Sendable {
    case packetBeforeLogin
    case duplicateLoginResponse
    case sessionNotReady
}

protocol APRSISMessaging: Actor {
    func events(
        identity: ReceiveOnlyAPRSIdentity,
        endpoint: APRSISEndpoint
    ) async -> AsyncThrowingStream<APRSISMessagingEvent, any Error>
    func send(packet: String) async throws
    func disconnect() async
}

actor APRSISMessagingClient: APRSISMessaging {
    private let transport: any APRSISByteTransport
    private let messagingProtocol: APRSISMessagingProtocol
    private let packetParser: TNC2PacketParser
    private let messageCodec: APRSMessageCodec
    private var streamTask: Task<Void, Never>?
    private var streamID: UUID?
    private var isReady = false

    init(
        transport: any APRSISByteTransport = NWAPRSISByteTransport(),
        messagingProtocol: APRSISMessagingProtocol,
        packetParser: TNC2PacketParser = TNC2PacketParser(),
        messageCodec: APRSMessageCodec = APRSMessageCodec()
    ) {
        self.transport = transport
        self.messagingProtocol = messagingProtocol
        self.packetParser = packetParser
        self.messageCodec = messageCodec
    }

    func events(
        identity: ReceiveOnlyAPRSIdentity,
        endpoint: APRSISEndpoint = .asia
    ) async -> AsyncThrowingStream<APRSISMessagingEvent, any Error> {
        await disconnect()
        let streamID = UUID()
        self.streamID = streamID
        return AsyncThrowingStream { continuation in
            let task = Task {
                await run(
                    identity: identity,
                    endpoint: endpoint,
                    streamID: streamID,
                    continuation: continuation
                )
            }
            streamTask = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func send(packet: String) async throws {
        guard isReady else { throw APRSISMessagingClientError.sessionNotReady }
        try await transport.send(try messagingProtocol.makePacketCommand(packet))
    }

    func disconnect() async {
        streamTask?.cancel()
        streamTask = nil
        streamID = nil
        isReady = false
        await transport.disconnect()
    }

    private func run(
        identity: ReceiveOnlyAPRSIdentity,
        endpoint: APRSISEndpoint,
        streamID: UUID,
        continuation: AsyncThrowingStream<APRSISMessagingEvent, any Error>.Continuation
    ) async {
        var framer = APRSISLineFramer()
        var sentLogin = false
        var acceptedLogin = false
        let expectedAddress = TNC2Address(callsign: identity.callsign, ssid: identity.ssid)

        do {
            try await transport.connect(to: endpoint)
            while !Task.isCancelled {
                let data = try await transport.receive(maximumLength: 4_096)
                for line in try framer.append(data) {
                    if line.hasPrefix("#") {
                        if line.lowercased().hasPrefix("# logresp") {
                            guard sentLogin, !acceptedLogin else {
                                throw APRSISMessagingClientError.duplicateLoginResponse
                            }
                            let response = try messagingProtocol.parseLoginResponse(
                                line,
                                expectedIdentity: identity
                            )
                            acceptedLogin = true
                            isReady = true
                            continuation.yield(.sessionReady(serverCallsign: response.serverCallsign))
                        } else if !sentLogin {
                            try await transport.send(try messagingProtocol.makeLoginCommand(for: identity))
                            sentLogin = true
                        }
                        continue
                    }

                    guard acceptedLogin else {
                        throw APRSISMessagingClientError.packetBeforeLogin
                    }
                    do {
                        let packet = try packetParser.parse(line)
                        let envelope = try messageCodec.decode(
                            packet,
                            expectedAddressee: expectedAddress
                        )
                        continuation.yield(.message(envelope))
                    } catch {
                        continuation.yield(.rejectedPacket)
                    }
                }
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }

        await transport.disconnect()
        if self.streamID == streamID {
            isReady = false
            streamTask = nil
            self.streamID = nil
        }
    }
}
