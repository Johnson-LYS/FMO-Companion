import Foundation
@preconcurrency import MQTTNIO
import NIOCore
import NIOFoundationCompat
import NIOPosix

protocol FMOMQTTTransport: Sendable {
    func connect(_ request: FMOMQTTConnectRequest) async throws
    func incomingRaw() async throws -> AsyncThrowingStream<Data, Error>
    func publishRaw(_ payload: Data) async throws
    func disconnect() async
}

nonisolated enum FMOMQTTTransportError: Error, Equatable, Sendable {
    case alreadyConnected
    case notConnected
    case subscriptionRejected
    case oversizedPayload
    case unexpectedTopic
}

actor MQTTNIOFMOMQTTTransport: FMOMQTTTransport {
    private var client: MQTTClient?
    private var listenerTask: Task<Void, Never>?
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?

    func connect(_ request: FMOMQTTConnectRequest) async throws {
        guard client == nil else { throw FMOMQTTTransportError.alreadyConnected }
        let configuration = MQTTClient.Configuration(
            version: .v3_1_1,
            disablePing: false,
            keepAliveInterval: .seconds(Int64(request.keepAliveSeconds)),
            pingInterval: .seconds(15),
            connectTimeout: .seconds(10),
            timeout: .seconds(10),
            userName: request.username,
            password: request.password,
            useSSL: request.usesTLS,
            sniServerName: request.tlsServerName
        )
        let mqtt = MQTTClient(
            host: request.host,
            port: Int(request.port),
            identifier: request.clientID,
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
            configuration: configuration
        )
        do {
            try await mqtt.connect(cleanSession: true)
            let acknowledgement = try await mqtt.subscribe(
                to: [MQTTSubscribeInfo(topicFilter: "FMO/RAW", qos: .atMostOnce)]
            )
            guard acknowledgement.returnCodes.allSatisfy({ $0 != .failure }) else {
                throw FMOMQTTTransportError.subscriptionRejected
            }
            client = mqtt
        } catch {
            try? await mqtt.shutdown()
            throw error
        }
    }

    func incomingRaw() throws -> AsyncThrowingStream<Data, Error> {
        guard let client else { throw FMOMQTTTransportError.notConnected }
        listenerTask?.cancel()
        continuation?.finish()
        let stream = AsyncThrowingStream<Data, Error>(bufferingPolicy: .bufferingNewest(16)) { continuation in
            self.continuation = continuation
        }
        let continuation = self.continuation
        listenerTask = Task {
            let listener = client.createPublishListener()
            for await result in listener {
                guard !Task.isCancelled else { break }
                switch result {
                case .success(let publish):
                    guard publish.topicName == "FMO/RAW" else { continue }
                    var payload = publish.payload
                    guard payload.readableBytes <= FMORawHeader.maximumPacketByteCount,
                          let data = payload.readData(length: payload.readableBytes) else { continue }
                    continuation?.yield(data)
                case .failure(let error):
                    continuation?.finish(throwing: error)
                    return
                }
            }
            continuation?.finish()
        }
        return stream
    }

    func publishRaw(_ payload: Data) async throws {
        guard let client else { throw FMOMQTTTransportError.notConnected }
        guard payload.count <= FMORawHeader.maximumPacketByteCount else {
            throw FMOMQTTTransportError.oversizedPayload
        }
        var buffer = ByteBufferAllocator().buffer(capacity: payload.count)
        buffer.writeBytes(payload)
        try await client.publish(to: "FMO/RAW", payload: buffer, qos: .atMostOnce, retain: false)
    }

    func disconnect() async {
        listenerTask?.cancel()
        listenerTask = nil
        continuation?.finish()
        continuation = nil
        guard let client else { return }
        self.client = nil
        try? await client.disconnect()
        try? await client.shutdown()
    }
}

actor DisabledFMOMQTTTransport: FMOMQTTTransport {
    func connect(_ request: FMOMQTTConnectRequest) throws { throw FMOMQTTTransportError.notConnected }
    func incomingRaw() throws -> AsyncThrowingStream<Data, Error> { throw FMOMQTTTransportError.notConnected }
    func publishRaw(_ payload: Data) throws { throw FMOMQTTTransportError.notConnected }
    func disconnect() {}
}
