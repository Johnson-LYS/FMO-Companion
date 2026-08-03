import Foundation
import Network
import Synchronization

nonisolated final class NWLocalNetworkChecker: FmoLocalNetworkChecking, @unchecked Sendable {
    func check() async throws {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.bi8syn.FMOc.diagnostics.path")
        let activeSession = Mutex<PathCheckSession?>(nil)
        let hasWiFi = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let session = PathCheckSession(monitor: monitor, continuation: continuation)
                activeSession.withLock { $0 = session }
                if Task.isCancelled {
                    session.cancel()
                    return
                }
                monitor.pathUpdateHandler = { path in
                    session.finish(
                        hasWiFi: path.availableInterfaces.contains { $0.type == .wifi }
                    )
                }
                monitor.start(queue: queue)
            }
        } onCancel: {
            activeSession.withLock { $0 }?.cancel()
        }

        try Task.checkCancellation()
        guard hasWiFi else { throw FmoDiagnosticFailure.wifiUnavailable }
    }
}

private nonisolated final class PathCheckSession: @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let continuation: CheckedContinuation<Bool, Never>
    private let finished = Mutex(false)

    init(monitor: NWPathMonitor, continuation: CheckedContinuation<Bool, Never>) {
        self.monitor = monitor
        self.continuation = continuation
    }

    func finish(hasWiFi: Bool) {
        let shouldFinish = finished.withLock { finished in
            guard !finished else { return false }
            finished = true
            return true
        }
        guard shouldFinish else { return }
        monitor.cancel()
        continuation.resume(returning: hasWiFi)
    }

    func cancel() {
        finish(hasWiFi: false)
    }
}

nonisolated final class NWEndpointChecker: FmoEndpointChecking, @unchecked Sendable {
    private let timeout: Duration

    init(timeout: Duration = .seconds(5)) {
        self.timeout = timeout
    }

    func check(_ endpoint: FmoDeviceEndpoint) async throws -> Int {
        try await withThrowingTaskGroup(of: Int.self) { group in
            group.addTask {
                try await self.open(endpoint)
            }
            group.addTask {
                try await Task.sleep(for: self.timeout)
                throw FmoDiagnosticFailure.timedOut
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw FmoDiagnosticFailure.endpointUnavailable
            }
            return result
        }
    }

    private func open(_ endpoint: FmoDeviceEndpoint) async throws -> Int {
        guard let port = NWEndpoint.Port(rawValue: UInt16(endpoint.port ?? 80)) else {
            throw FmoDiagnosticFailure.endpointUnavailable
        }

        let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: .tcp)
        let queue = DispatchQueue(label: "com.bi8syn.FMOc.diagnostics.endpoint")
        let stream = AsyncThrowingStream<Int, any Error> { continuation in
            let session = EndpointCheckSession(connection: connection, continuation: continuation)
            connection.stateUpdateHandler = { state in session.handle(state, port: Int(port.rawValue)) }
            continuation.onTermination = { @Sendable _ in session.cancel() }
            connection.start(queue: queue)
        }

        for try await resolvedPort in stream {
            return resolvedPort
        }
        throw FmoDiagnosticFailure.endpointUnavailable
    }
}

private nonisolated final class EndpointCheckSession: @unchecked Sendable {
    private let connection: NWConnection
    private let continuation: AsyncThrowingStream<Int, any Error>.Continuation
    private let finished = Mutex(false)

    init(
        connection: NWConnection,
        continuation: AsyncThrowingStream<Int, any Error>.Continuation
    ) {
        self.connection = connection
        self.continuation = continuation
    }

    func handle(_ state: NWConnection.State, port: Int) {
        switch state {
        case .ready:
            finish(port: port)
        case .waiting(let error):
            if let failure = diagnosticFailure(for: error) {
                finish(throwing: failure)
            }
        case .failed(let error):
            finish(throwing: diagnosticFailure(for: error) ?? .endpointUnavailable)
        case .cancelled:
            finish(throwing: CancellationError())
        case .setup, .preparing:
            break
        @unknown default:
            break
        }
    }

    func cancel() {
        finish(throwing: CancellationError())
    }

    private func diagnosticFailure(for error: NWError) -> FmoDiagnosticFailure? {
        guard case .dns(let code) = error else { return nil }
        return Int32(code) == -65_570 ? .localNetworkDenied : .resolutionFailed
    }

    private func finish(port: Int? = nil, throwing error: (any Error)? = nil) {
        let shouldFinish = finished.withLock { finished in
            guard !finished else { return false }
            finished = true
            return true
        }
        guard shouldFinish else { return }

        connection.cancel()
        if let port {
            continuation.yield(port)
            continuation.finish()
        } else if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}

actor URLSessionFmoHTTPChecker: FmoHTTPChecking {
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        self.session = URLSession(configuration: configuration)
    }

    func check(_ endpoint: FmoDeviceEndpoint) async throws -> Int {
        var components = URLComponents()
        components.scheme = "http"
        components.host = endpoint.host
        components.port = endpoint.port
        components.path = "/"
        guard let url = components.url else { throw FmoDiagnosticFailure.httpUnavailable }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw FmoDiagnosticFailure.httpUnavailable
        }
        return response.statusCode
    }
}

actor FmoGeoChecker: FmoGeoChecking {
    private let makeClient: @Sendable () -> any FmoGeoClient

    init(makeClient: @escaping @Sendable () -> any FmoGeoClient = { FmoGeoWebSocketClient() }) {
        self.makeClient = makeClient
    }

    func check(_ endpoint: FmoDeviceEndpoint) async throws {
        let client = makeClient()
        do {
            try await client.connect(to: endpoint)
            _ = try await client.getCoordinate()
            await client.disconnect()
        } catch {
            await client.disconnect()
            throw error
        }
    }
}
