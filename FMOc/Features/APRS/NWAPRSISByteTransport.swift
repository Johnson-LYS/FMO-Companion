@preconcurrency import Network
import Foundation

actor NWAPRSISByteTransport: APRSISByteTransport {
    private let queue = DispatchQueue(label: "com.bi8syn.FMOc.aprs-is")
    private var connection: NWConnection?
    private var connectionID: UUID?
    private var connectContinuation: CheckedContinuation<Void, any Error>?

    func connect(to endpoint: APRSISEndpoint) async throws {
        await disconnect()

        guard
            !endpoint.host.isEmpty,
            let port = NWEndpoint.Port(rawValue: endpoint.port)
        else {
            throw APRSISTransportError.invalidEndpoint
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        let connection = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: port,
            using: parameters
        )
        let connectionID = UUID()
        self.connection = connection
        self.connectionID = connectionID

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                connectContinuation = continuation
                connection.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        Task { await self?.handleReady(connectionID: connectionID) }
                    case .failed:
                        Task { await self?.handleFailure(connectionID: connectionID) }
                    case .cancelled:
                        Task { await self?.handleCancellation(connectionID: connectionID) }
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            connection.cancel()
        }
    }

    func send(_ data: Data) async throws {
        guard let connection else {
            throw APRSISTransportError.disconnected
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                connection.send(
                    content: data,
                    completion: .contentProcessed { error in
                        if error == nil {
                            continuation.resume()
                        } else {
                            continuation.resume(
                                throwing: APRSISTransportError.sendFailed
                            )
                        }
                    }
                )
            }
        } onCancel: {
            connection.cancel()
        }
    }

    func receive(maximumLength: Int) async throws -> Data {
        guard let connection else {
            throw APRSISTransportError.disconnected
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                connection.receive(
                    minimumIncompleteLength: 1,
                    maximumLength: maximumLength
                ) { data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(
                            throwing: APRSISTransportError.disconnected
                        )
                    } else if error != nil {
                        continuation.resume(
                            throwing: APRSISTransportError.receiveFailed
                        )
                    } else {
                        continuation.resume(
                            throwing: APRSISTransportError.receiveFailed
                        )
                    }
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    func disconnect() async {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        connectionID = nil
        connectContinuation?.resume(
            throwing: APRSISTransportError.disconnected
        )
        connectContinuation = nil
    }

    private func handleReady(connectionID: UUID) {
        guard self.connectionID == connectionID else { return }
        connectContinuation?.resume()
        connectContinuation = nil
    }

    private func handleFailure(connectionID: UUID) {
        guard self.connectionID == connectionID else { return }
        connectContinuation?.resume(
            throwing: APRSISTransportError.connectionFailed
        )
        connectContinuation = nil
        connection = nil
        self.connectionID = nil
    }

    private func handleCancellation(connectionID: UUID) {
        guard self.connectionID == connectionID else { return }
        connectContinuation?.resume(
            throwing: APRSISTransportError.disconnected
        )
        connectContinuation = nil
        connection = nil
        self.connectionID = nil
    }
}
