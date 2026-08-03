import Foundation

nonisolated protocol FmoWebSocketTransport: Sendable {
    func connect(to url: URL) async throws
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func disconnect() async
}

actor URLSessionFmoWebSocketTransport: FmoWebSocketTransport {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: configuration)
    }

    func connect(to url: URL) async throws {
        if task != nil { await disconnect() }
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
    }

    func send(_ data: Data) async throws {
        guard let task else { throw FmoDeviceError.disconnected }
        guard let text = String(data: data, encoding: .utf8) else {
            throw FmoDeviceError.protocolViolation
        }
        try await task.send(.string(text))
    }

    func receive() async throws -> Data {
        guard let task else { throw FmoDeviceError.disconnected }
        switch try await task.receive() {
        case .data(let data):
            return data
        case .string(let text):
            return Data(text.utf8)
        @unknown default:
            throw FmoDeviceError.unsupportedResponse
        }
    }

    func disconnect() async {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}
