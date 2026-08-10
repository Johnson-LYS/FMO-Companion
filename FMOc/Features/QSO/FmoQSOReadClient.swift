import Foundation

nonisolated protocol FmoQSOReading: Sendable {
    func connect(to endpoint: FmoDeviceEndpoint) async throws
    func list(page: Int, pageSize: Int) async throws -> FmoQSOListPage
    func detail(logID: Int64) async throws -> FmoQSODetail
    func disconnect() async
}

actor FmoQSOReadClient: FmoQSOReading {
    nonisolated struct Policy: Sendable {
        var responseTimeout: Duration = .seconds(5)
        var maximumResponseBytes = 512 * 1_024
    }

    private let transport: any FmoWebSocketTransport
    private let codec: FmoQSOProtocol
    private let policy: Policy
    private var connectedEndpoint: FmoDeviceEndpoint?
    private var exchangeInProgress = false
    private var exchangeWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        transport: any FmoWebSocketTransport = URLSessionFmoWebSocketTransport(),
        codec: FmoQSOProtocol = FmoQSOProtocol(),
        policy: Policy = Policy()
    ) {
        self.transport = transport
        self.codec = codec
        self.policy = policy
    }

    func connect(to endpoint: FmoDeviceEndpoint) async throws {
        if connectedEndpoint == endpoint { return }
        await transport.disconnect()
        do {
            try await transport.connect(to: endpoint.webSocketURL)
            connectedEndpoint = endpoint
        } catch is CancellationError {
            throw FmoDeviceError.operationCancelled
        } catch {
            throw FmoDeviceError.handshakeFailed
        }
    }

    func list(page: Int, pageSize: Int) async throws -> FmoQSOListPage {
        await acquireExchangeSlot()
        defer { releaseExchangeSlot() }
        try Task.checkCancellation()
        guard case let .list(value) = try await exchange(.list(page: page, pageSize: pageSize)) else {
            throw FmoDeviceError.protocolViolation
        }
        return value
    }

    func detail(logID: Int64) async throws -> FmoQSODetail {
        await acquireExchangeSlot()
        defer { releaseExchangeSlot() }
        try Task.checkCancellation()
        guard case let .detail(value) = try await exchange(.detail(logID: logID)) else {
            throw FmoDeviceError.protocolViolation
        }
        return value
    }

    func disconnect() async {
        connectedEndpoint = nil
        await transport.disconnect()
    }

    private func exchange(_ command: FmoQSOProtocol.Command) async throws -> FmoQSOProtocol.Response {
        guard connectedEndpoint != nil else { throw FmoDeviceError.disconnected }
        do {
            try await transport.send(codec.makeRequest(for: command))
            let transport = self.transport
            let codec = self.codec
            let timeout = policy.responseTimeout
            let maximumResponseBytes = policy.maximumResponseBytes
            return try await withThrowingTaskGroup(of: FmoQSOProtocol.Response.self) { group in
                group.addTask {
                    let data = try await transport.receive()
                    guard data.count <= maximumResponseBytes else {
                        throw FmoDeviceError.protocolViolation
                    }
                    return try codec.decodeResponse(data, for: command)
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw FmoDeviceError.responseTimedOut
                }
                defer { group.cancelAll() }
                guard let response = try await group.next() else { throw FmoDeviceError.disconnected }
                return response
            }
        } catch let error as FmoDeviceError {
            if case .deviceRejected = error {
                throw error
            }
            await invalidateConnection()
            throw error
        } catch is CancellationError {
            await invalidateConnection()
            throw FmoDeviceError.operationCancelled
        } catch {
            await invalidateConnection()
            throw FmoDeviceError.disconnected
        }
    }

    private func invalidateConnection() async {
        connectedEndpoint = nil
        await transport.disconnect()
    }

    private func acquireExchangeSlot() async {
        if !exchangeInProgress {
            exchangeInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            exchangeWaiters.append(continuation)
        }
    }

    private func releaseExchangeSlot() {
        if exchangeWaiters.isEmpty {
            exchangeInProgress = false
        } else {
            exchangeWaiters.removeFirst().resume()
        }
    }
}

actor UnavailableFmoQSOReader: FmoQSOReading {
    func connect(to endpoint: FmoDeviceEndpoint) throws { throw FmoDeviceError.networkUnavailable }
    func list(page: Int, pageSize: Int) throws -> FmoQSOListPage { throw FmoDeviceError.networkUnavailable }
    func detail(logID: Int64) throws -> FmoQSODetail { throw FmoDeviceError.networkUnavailable }
    func disconnect() {}
}
