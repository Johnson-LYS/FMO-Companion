import Foundation

actor FmoGeoWebSocketClient: FmoGeoClient {
    nonisolated struct Policy: Sendable {
        var responseTimeout: Duration = .seconds(5)
    }

    private let transport: any FmoWebSocketTransport
    private let codec: FmoGeoProtocol
    private let policy: Policy
    private var connectedEndpoint: FmoDeviceEndpoint?

    init(
        transport: any FmoWebSocketTransport = URLSessionFmoWebSocketTransport(),
        codec: FmoGeoProtocol = FmoGeoProtocol(),
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

    func getCoordinate() async throws -> GeoCoordinate {
        guard connectedEndpoint != nil else { throw FmoDeviceError.disconnected }
        let response = try await exchange(codec.makeGetCoordinateRequest())
        guard case .coordinate(let coordinate) = response else {
            throw FmoDeviceError.unsupportedResponse
        }
        return coordinate
    }

    func setCoordinate(_ coordinate: GeoCoordinate) async throws {
        guard connectedEndpoint != nil else { throw FmoDeviceError.disconnected }
        let response = try await exchange(codec.makeSetCoordinateRequest(coordinate))
        guard response == .coordinateSet else { throw FmoDeviceError.unsupportedResponse }
    }

    func disconnect() async {
        connectedEndpoint = nil
        await transport.disconnect()
    }

    private func exchange(_ request: Data) async throws -> FmoGeoProtocol.Response {
        do {
            try await transport.send(request)
            let transport = self.transport
            let codec = self.codec
            let timeout = policy.responseTimeout

            return try await withThrowingTaskGroup(of: FmoGeoProtocol.Response.self) { group in
                group.addTask {
                    try codec.decodeResponse(await transport.receive())
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw FmoDeviceError.responseTimedOut
                }

                defer { group.cancelAll() }
                guard let result = try await group.next() else {
                    throw FmoDeviceError.disconnected
                }
                return result
            }
        } catch let error as FmoDeviceError {
            if error == .disconnected {
                await invalidateConnection()
            }
            throw error
        } catch is CancellationError {
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
