import Foundation

actor FmoLocalStatusWebSocketClient: FmoLocalStatusProviding {
    nonisolated struct Policy: Sendable {
        var responseTimeout: Duration = .seconds(5)
        var maximumResponseBytes = 256 * 1_024
    }

    private let transport: any FmoWebSocketTransport
    private let codec: FmoLocalStatusProtocol
    private let policy: Policy
    private var connectedEndpoint: FmoDeviceEndpoint?

    init(
        transport: any FmoWebSocketTransport = URLSessionFmoWebSocketTransport(),
        codec: FmoLocalStatusProtocol = FmoLocalStatusProtocol(),
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

    func getCallsign() async throws -> String {
        guard case .callsign(let value) = try await exchange(.callsign) else {
            throw FmoDeviceError.protocolViolation
        }
        return value
    }

    func getCurrentServer() async throws -> FmoCurrentServer {
        guard case .currentServer(let value) = try await exchange(.currentServer) else {
            throw FmoDeviceError.protocolViolation
        }
        return value
    }

    func getServerFilter() async throws -> FmoServerFilter {
        guard case .serverFilter(let value) = try await exchange(.serverFilter) else {
            throw FmoDeviceError.protocolViolation
        }
        return value
    }

    func getWorkingFrequencyMHz() async throws -> Double {
        guard case .workingFrequencyMHz(let value) = try await exchange(.workingFrequency) else {
            throw FmoDeviceError.protocolViolation
        }
        return value
    }

    func getQSOLogCount() async throws -> Int {
        guard case .qsoLogCount(let value) = try await exchange(.qsoLogCount) else {
            throw FmoDeviceError.protocolViolation
        }
        return value
    }

    func disconnect() async {
        connectedEndpoint = nil
        await transport.disconnect()
    }

    private func exchange(_ command: FmoLocalStatusProtocol.Command) async throws -> FmoLocalStatusProtocol.Response {
        guard connectedEndpoint != nil else { throw FmoDeviceError.disconnected }
        do {
            try await transport.send(codec.makeRequest(for: command))
            let transport = self.transport
            let codec = self.codec
            let timeout = policy.responseTimeout
            let maximumResponseBytes = policy.maximumResponseBytes

            return try await withThrowingTaskGroup(of: FmoLocalStatusProtocol.Response.self) { group in
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
