import Foundation

actor FmoLocalEventWebSocketClient: FmoLocalEventStreaming {
    nonisolated struct Policy: Sendable {
        var maximumEventBytes = 64 * 1_024
    }

    private let transport: any FmoWebSocketTransport
    private let codec: FmoLocalEventProtocol
    private let policy: Policy
    private var streamTask: Task<Void, Never>?

    init(
        transport: any FmoWebSocketTransport = URLSessionFmoWebSocketTransport(),
        codec: FmoLocalEventProtocol = FmoLocalEventProtocol(),
        policy: Policy = Policy()
    ) {
        self.transport = transport
        self.codec = codec
        self.policy = policy
    }

    func events(from endpoint: FmoDeviceEndpoint) async -> AsyncThrowingStream<FmoLocalEvent, any Error> {
        await disconnect()

        return AsyncThrowingStream { continuation in
            let transport = self.transport
            let codec = self.codec
            let maximumEventBytes = policy.maximumEventBytes
            let task = Task {
                do {
                    try await transport.connect(to: endpoint.eventWebSocketURL)
                    while !Task.isCancelled {
                        let data = try await transport.receive()
                        guard data.count <= maximumEventBytes else {
                            throw FmoDeviceError.protocolViolation
                        }
                        if let event = try codec.decodeEvent(data) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                await transport.disconnect()
            }
            streamTask = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func disconnect() async {
        streamTask?.cancel()
        streamTask = nil
        await transport.disconnect()
    }
}
