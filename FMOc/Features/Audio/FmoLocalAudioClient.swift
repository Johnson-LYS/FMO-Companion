import Foundation

nonisolated enum FmoAudioWebSocketMessage: Equatable, Sendable {
    case binary(Data)
    case text(String)
    case unsupported
}

nonisolated protocol FmoAudioWebSocketTransport: Sendable {
    func connect(to url: URL) async throws
    func receive() async throws -> FmoAudioWebSocketMessage
    func disconnect() async
}

actor URLSessionFmoAudioWebSocketTransport: FmoAudioWebSocketTransport {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    func connect(to url: URL) async throws {
        disconnect()
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
    }

    func receive() async throws -> FmoAudioWebSocketMessage {
        guard let task else { throw FmoDeviceError.disconnected }
        switch try await task.receive() {
        case .data(let data): return FmoAudioWebSocketMessage.binary(data)
        case .string(let text): return FmoAudioWebSocketMessage.text(text)
        @unknown default: return FmoAudioWebSocketMessage.unsupported
        }
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}

nonisolated protocol FmoLocalAudioStreaming: Sendable {
    func frames(from endpoint: FmoDeviceEndpoint) async -> AsyncThrowingStream<FmoPCMFrame, any Error>
    func disconnect() async
}

actor FmoLocalAudioClient: FmoLocalAudioStreaming {
    private let transport: any FmoAudioWebSocketTransport
    private let codec: FmoLocalAudioProtocol
    private var streamTask: Task<Void, Never>?

    init(
        transport: any FmoAudioWebSocketTransport = URLSessionFmoAudioWebSocketTransport(),
        codec: FmoLocalAudioProtocol = FmoLocalAudioProtocol()
    ) {
        self.transport = transport
        self.codec = codec
    }

    func frames(from endpoint: FmoDeviceEndpoint) async -> AsyncThrowingStream<FmoPCMFrame, any Error> {
        await disconnect()

        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(4)) { continuation in
            let transport = self.transport
            let codec = self.codec
            let task = Task {
                do {
                    try await transport.connect(to: endpoint.audioWebSocketURL)
                    while !Task.isCancelled {
                        switch try await transport.receive() {
                        case .binary(let data):
                            continuation.yield(try codec.decodePCM(data))
                        case .text("p"):
                            continue
                        case .text:
                            throw FmoLocalAudioError.unexpectedText
                        case .unsupported:
                            throw FmoLocalAudioError.unsupportedMessage
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
        let task = streamTask
        streamTask = nil
        task?.cancel()
        await transport.disconnect()
        await task?.value
    }
}

nonisolated struct UnavailableFmoLocalAudioStream: FmoLocalAudioStreaming {
    func frames(from endpoint: FmoDeviceEndpoint) async -> AsyncThrowingStream<FmoPCMFrame, any Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }

    func disconnect() async {}
}
