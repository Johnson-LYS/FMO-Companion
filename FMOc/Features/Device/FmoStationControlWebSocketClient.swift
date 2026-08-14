import Foundation

actor FmoStationControlWebSocketClient: FmoStationControlling {
    nonisolated struct Policy: Sendable {
        var responseTimeout: Duration = .seconds(5)
        var verificationDelay: Duration = .seconds(1)
        var pageSize = 8
        var maximumServerCount = 1_024
        var maximumResponseBytes = 256 * 1_024
    }

    private let transport: any FmoWebSocketTransport
    private let codec: FmoStationControlProtocol
    private let policy: Policy
    private var connectedEndpoint: FmoDeviceEndpoint?

    init(
        transport: any FmoWebSocketTransport = URLSessionFmoWebSocketTransport(),
        codec: FmoStationControlProtocol = FmoStationControlProtocol(),
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

    func getServerCatalog() async throws -> FmoDeviceServerCatalog {
        try await getServerCatalog(onUpdate: { _ in })
    }

    func getServerCatalog(
        onUpdate: @escaping @Sendable (FmoDeviceServerCatalog) async -> Void
    ) async throws -> FmoDeviceServerCatalog {
        let all = try await loadAllPages(pinned: false) { partialAll in
            await onUpdate(FmoDeviceServerCatalog(all: partialAll, pinned: []))
        }
        let pinned = try await loadAllPages(pinned: true) { partialPinned in
            await onUpdate(FmoDeviceServerCatalog(all: all, pinned: partialPinned))
        }
        return FmoDeviceServerCatalog(all: all, pinned: pinned)
    }

    func switchCurrentServer(toUID uid: Int64) async throws -> FmoCurrentServer {
        guard uid > 0 else { throw FmoDeviceError.protocolViolation }
        guard case .currentServerAccepted = try await exchange(.setCurrentServer(uid: uid)) else {
            throw FmoDeviceError.protocolViolation
        }

        try await Task.sleep(for: policy.verificationDelay)
        guard case .currentServer(let current) = try await exchange(.currentServer), current.uid == uid else {
            throw FmoDeviceError.unsupportedResponse
        }
        return current
    }

    func disconnect() async {
        connectedEndpoint = nil
        await transport.disconnect()
    }

    private func loadAllPages(
        pinned: Bool,
        onUpdate: @escaping @Sendable ([FmoDeviceServer]) async -> Void
    ) async throws -> [FmoDeviceServer] {
        var result: [FmoDeviceServer] = []
        var seen = Set<Int64>()
        var offset = 0

        while result.count < policy.maximumServerCount {
            let command: FmoStationControlProtocol.Command = pinned
                ? .pinnedServers(start: offset, count: policy.pageSize)
                : .allServers(start: offset, count: policy.pageSize)
            guard case let .servers(page, count) = try await exchange(command) else {
                throw FmoDeviceError.protocolViolation
            }
            guard count == page.count else { throw FmoDeviceError.protocolViolation }
            for server in page where seen.insert(server.uid).inserted {
                result.append(server)
            }
            await onUpdate(result)
            offset += count
            guard count == policy.pageSize else { break }
            guard !page.isEmpty else { throw FmoDeviceError.protocolViolation }
        }

        return result
    }

    private func exchange(_ command: FmoStationControlProtocol.Command) async throws -> FmoStationControlProtocol.Response {
        guard connectedEndpoint != nil else { throw FmoDeviceError.disconnected }
        do {
            try await transport.send(codec.makeRequest(for: command))
            let transport = self.transport
            let codec = self.codec
            let timeout = policy.responseTimeout
            let maximumResponseBytes = policy.maximumResponseBytes

            return try await withThrowingTaskGroup(of: FmoStationControlProtocol.Response.self) { group in
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
                guard let result = try await group.next() else { throw FmoDeviceError.disconnected }
                return result
            }
        } catch let error as FmoDeviceError {
            switch error {
            case .deviceRejected:
                break
            default:
                await invalidateConnection()
            }
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
}
