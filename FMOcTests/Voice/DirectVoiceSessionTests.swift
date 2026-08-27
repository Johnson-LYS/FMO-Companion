import Foundation
import Testing
@testable import FMOc

struct DirectVoiceSessionTests {
    @Test func pttPublishesFiveEncodedFramesAndReturnsToListening() async throws {
        let suiteName = "DirectVoiceSessionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profileStore = UserDefaultsFMOServerProfileStore(defaults: defaults)
        try profileStore.save(Self.profile)
        let transport = RecordingVoiceTransport()
        let session = DirectVoiceSession(
            identityProvider: StubVoiceIdentityProvider(identity: Self.identity),
            profileStore: profileStore,
            transport: transport,
            codec: StubVoiceCodec(),
            installSuffix: "test"
        )

        await session.start()
        #expect(await session.currentSnapshot().phase == .listening)
        try await session.beginTransmit()
        #expect(await session.currentSnapshot().phase.isTransmitting)
        await session.appendCapturedSamples([Int16](repeating: 123, count: 320 * 5))
        #expect(await transport.publishedPayloads().count == 1)

        let packet = try FMORawParser().parse(try #require(await transport.publishedPayloads().first))
        #expect(packet.frames.count == 5)
        #expect(packet.header.uid == Self.identity.uid)
        #expect(packet.header.vendor == 0x2000)

        await session.endTransmit()
        #expect(await session.currentSnapshot().phase == .listening)
        await session.stop()
    }

    @Test func mutedReceiveAdvancesDecoderAndNewStreamResetsIt() async throws {
        let suiteName = "DirectVoiceMutedReceiveTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profileStore = UserDefaultsFMOServerProfileStore(defaults: defaults)
        try profileStore.save(Self.profile)
        let transport = RecordingVoiceTransport()
        let codec = ObservingVoiceCodec()
        let session = DirectVoiceSession(
            identityProvider: StubVoiceIdentityProvider(identity: Self.identity),
            profileStore: profileStore,
            transport: transport,
            codec: codec,
            installSuffix: "test"
        )

        await session.start()
        await session.setMuted(true)
        try await transport.yield(Self.incomingPacket(streamBeginUTC: 100))
        try await codec.waitForDecodedFrames(1)
        #expect(await codec.resetCount() == 1)

        try await transport.yield(Self.incomingPacket(streamBeginUTC: 200))
        try await codec.waitForDecodedFrames(2)
        #expect(await codec.resetCount() == 2)
        await session.stop()
    }

    private static func incomingPacket(streamBeginUTC: UInt32) throws -> Data {
        try FMORawEncoder().encode(
            uid: 42,
            callsign: "BG5ESN",
            streamBeginUTC: streamBeginUTC,
            timestamp: streamBeginUTC,
            serverUID: profile.serverUID,
            frames: [Data([0xF8, 0xFF, 0xFE])]
        )
    }

    private static let userCertificateJSON = Data(
        """
        {"type":"userCert","issuerSn":1001,"subject":{"callsign":"BI8SYN","uid":1000000001,"publicKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"},"iat":1700000000,"exp":4102444800,"signatureAlgorithm":"Ed25519","signature":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}
        """.utf8
    )

    private static let identity = DirectVoiceIdentity(
        callsign: "BI8SYN",
        uid: 1_000_000_001,
        issuedAt: 1_700_000_000,
        expiresAt: 4_102_444_800,
        issuerSerialNumber: 1_001,
        rootFingerprint: Data(repeating: 0x11, count: 32),
        intermediateCertificateJSON: Data("{\"type\":\"intermediateCA\"}".utf8),
        userCertificateJSON: userCertificateJSON
    )

    private static let profile = FMOServerProfile(
        displayName: "Test",
        dialHost: "mqtt.example.invalid",
        targetHost: "mqtt.example.invalid",
        mqttPort: 8_883,
        serverUID: 5_001,
        serverCallsign: "BG5ESN",
        serverCertificateFingerprint: Data(repeating: 0x22, count: 32)
    )
}

private nonisolated extension DirectVoiceSessionPhase {
    var isTransmitting: Bool {
        if case .transmitting = self { return true }
        return false
    }
}

private nonisolated struct StubVoiceIdentityProvider: DirectVoiceIdentityProviding {
    let identity: DirectVoiceIdentity

    func enrollmentRequest(callsign: String) throws -> DirectVoiceEnrollmentRequest {
        DirectVoiceEnrollmentRequest(callsign: callsign, publicKeyBase64URL: "")
    }
    func importSignedBundle(_ data: Data, now: Date) throws -> DirectVoiceIdentity { identity }
    func storedIdentities() throws -> [DirectVoiceIdentity] { [identity] }
    func currentIdentity(now: Date) throws -> DirectVoiceIdentity { identity }
    func selectIdentity(id: String, now: Date) throws -> DirectVoiceIdentity { identity }
    func sign(_ data: Data, identityID: String) -> Data { Data(repeating: 0x33, count: 64) }
    func installationSuffix() -> String { "test" }
    func removeIdentity(id: String, now: Date) {}
}

private actor RecordingVoiceTransport: FMOMQTTTransport {
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var published: [Data] = []

    func connect(_ request: FMOMQTTConnectRequest) {}

    func incomingRaw() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in self.continuation = continuation }
    }

    func publishRaw(_ payload: Data) { published.append(payload) }

    func disconnect() {
        continuation?.finish()
        continuation = nil
    }

    func yield(_ payload: Data) throws {
        guard let continuation else { throw FMOMQTTTransportError.notConnected }
        continuation.yield(payload)
    }

    func publishedPayloads() -> [Data] { published }
}

private actor ObservingVoiceCodec: FMOAudioCodec {
    private var decodedFrames = 0
    private var resets = 0

    func encode40ms(_ pcm: [Int16]) -> Data { Data([0xF8, 0xFF, 0xFE]) }

    func decode40ms(_ data: Data) -> [Int16] {
        decodedFrames += 1
        return [Int16](repeating: 0, count: 320)
    }

    func concealLoss() -> [Int16] { [Int16](repeating: 0, count: 320) }

    func reset() {
        resets += 1
    }

    func resetCount() -> Int { resets }

    func waitForDecodedFrames(_ expected: Int) async throws {
        for _ in 0 ..< 100 {
            if decodedFrames >= expected { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw DirectVoiceSessionTestError.timedOut
    }
}

private enum DirectVoiceSessionTestError: Error {
    case timedOut
}

private actor StubVoiceCodec: FMOAudioCodec {
    func encode40ms(_ pcm: [Int16]) throws -> Data {
        guard pcm.count == 320 else { throw FMOAudioCodecError.invalidPCMFrame }
        return Data([0xF8, 0xFF, 0xFE])
    }
    func decode40ms(_ data: Data) -> [Int16] { [Int16](repeating: 0, count: 320) }
    func concealLoss() -> [Int16] { [Int16](repeating: 0, count: 320) }
    func reset() {}
}
