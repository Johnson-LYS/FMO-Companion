import Foundation

nonisolated enum APRSISFrameRejection: Equatable, Sendable {
    case invalidTNC2
    case invalidFMOV4
}

nonisolated enum APRSISInboundEvent: Equatable, Sendable {
    case frame(UnverifiedFMOV4Frame)
    case rejected(APRSISFrameRejection)
}

nonisolated enum APRSISReceiveOnlyClientError: Error, Equatable, Sendable {
    case packetBeforeLogin
    case duplicateLoginResponse
}

protocol APRSISReceiving: Actor {
    func events(
        identity: ReceiveOnlyAPRSIdentity,
        endpoint: APRSISEndpoint
    ) async -> AsyncThrowingStream<APRSISInboundEvent, any Error>
    func disconnect() async
}

actor APRSISReceiveOnlyClient: APRSISReceiving {
    nonisolated struct Policy: Sendable {
        var maximumReceiveByteCount = 4_096
    }

    private let transport: any APRSISByteTransport
    private let aprsISProtocol: APRSISProtocol
    private let tnc2Parser: TNC2PacketParser
    private let fmoV4Parser: FMOV4Parser
    private let policy: Policy
    private var streamTask: Task<Void, Never>?
    private var streamID: UUID?

    init(
        transport: any APRSISByteTransport = NWAPRSISByteTransport(),
        aprsISProtocol: APRSISProtocol,
        tnc2Parser: TNC2PacketParser = TNC2PacketParser(),
        fmoV4Parser: FMOV4Parser = FMOV4Parser(),
        policy: Policy = Policy()
    ) {
        self.transport = transport
        self.aprsISProtocol = aprsISProtocol
        self.tnc2Parser = tnc2Parser
        self.fmoV4Parser = fmoV4Parser
        self.policy = policy
    }

    func events(
        identity: ReceiveOnlyAPRSIdentity,
        endpoint: APRSISEndpoint = .asia
    ) async -> AsyncThrowingStream<APRSISInboundEvent, any Error> {
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

    func disconnect() async {
        streamTask?.cancel()
        streamTask = nil
        streamID = nil
        await transport.disconnect()
    }

    private func run(
        identity: ReceiveOnlyAPRSIdentity,
        endpoint: APRSISEndpoint,
        streamID: UUID,
        continuation: AsyncThrowingStream<APRSISInboundEvent, any Error>.Continuation
    ) async {
        var lineFramer = APRSISLineFramer()
        var sentLogin = false
        var acceptedLogin = false

        do {
            try await transport.connect(to: endpoint)

            while !Task.isCancelled {
                let data = try await transport.receive(
                    maximumLength: policy.maximumReceiveByteCount
                )
                let lines = try lineFramer.append(data)

                for line in lines {
                    if line.hasPrefix("#") {
                        if line.lowercased().hasPrefix("# logresp") {
                            guard sentLogin, !acceptedLogin else {
                                throw APRSISReceiveOnlyClientError.duplicateLoginResponse
                            }
                            _ = try aprsISProtocol.parseLoginResponse(
                                line,
                                expectedIdentity: identity
                            )
                            acceptedLogin = true
                        } else if !sentLogin {
                            try await transport.send(
                                aprsISProtocol.makeLoginCommand(for: identity)
                            )
                            sentLogin = true
                        }
                        continue
                    }

                    guard acceptedLogin else {
                        throw APRSISReceiveOnlyClientError.packetBeforeLogin
                    }

                    let packet: TNC2Packet
                    do {
                        packet = try tnc2Parser.parse(line)
                    } catch {
                        continuation.yield(.rejected(.invalidTNC2))
                        continue
                    }

                    do {
                        continuation.yield(.frame(try fmoV4Parser.parse(packet)))
                    } catch {
                        continuation.yield(.rejected(.invalidFMOV4))
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
            streamTask = nil
            self.streamID = nil
        }
    }
}
