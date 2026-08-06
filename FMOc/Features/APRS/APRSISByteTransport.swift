import Foundation

nonisolated struct APRSISEndpoint: Equatable, Hashable, Sendable {
    static let asia = APRSISEndpoint(host: "asia.aprs2.net", port: 14_580)

    let host: String
    let port: UInt16
}

nonisolated enum APRSISTransportError: Error, Equatable, Sendable {
    case invalidEndpoint
    case connectionFailed
    case disconnected
    case sendFailed
    case receiveFailed
}

protocol APRSISByteTransport: Actor {
    func connect(to endpoint: APRSISEndpoint) async throws
    func send(_ data: Data) async throws
    func receive(maximumLength: Int) async throws -> Data
    func disconnect() async
}
