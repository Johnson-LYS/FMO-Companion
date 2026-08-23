import Foundation

nonisolated enum DirectVoiceSessionPhase: Equatable, Sendable {
    case idle
    case connecting
    case listening
    case receiving(callsign: String)
    case transmitting(startedAt: Date)
    case busy
    case failed(message: String)
}

nonisolated struct DirectVoiceSessionSnapshot: Equatable, Sendable {
    var phase: DirectVoiceSessionPhase = .idle
    var isMuted = false
    var currentCallsign: String?
}

actor DirectVoiceSession {
    private let identityProvider: any DirectVoiceIdentityProviding
    private let profileStore: UserDefaultsFMOServerProfileStore
    private let transport: any FMOMQTTTransport
    private let codec: any FMOAudioCodec
    private let authBuilder = SASAuthPayloadBuilder()
    private let rawEncoder = FMORawEncoder()
    private let rawParser = FMORawParser()

    private var snapshot = DirectVoiceSessionSnapshot()
    private var stateContinuation: AsyncStream<DirectVoiceSessionSnapshot>.Continuation?
    private var playbackContinuation: AsyncStream<[Int16]>.Continuation?
    private var receiveTask: Task<Void, Never>?
    private var receiveIdleTask: Task<Void, Never>?
    private var transmitLimitTask: Task<Void, Never>?
    private var routeArbiter = FMOVoiceRouteArbiter()
    private var identity: DirectVoiceIdentity?
    private var profile: FMOServerProfile?
    private var captureBuffer: [Int16] = []
    private var encodedFrames: [Data] = []
    private var streamBeginUTC: UInt32?
    private let installSuffixOverride: String?

    init(
        identityProvider: any DirectVoiceIdentityProviding,
        profileStore: UserDefaultsFMOServerProfileStore,
        transport: any FMOMQTTTransport,
        codec: any FMOAudioCodec,
        installSuffix: String? = nil
    ) {
        self.identityProvider = identityProvider
        self.profileStore = profileStore
        self.transport = transport
        self.codec = codec
        installSuffixOverride = installSuffix
    }

    func states() -> AsyncStream<DirectVoiceSessionSnapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            stateContinuation = continuation
            continuation.yield(snapshot)
        }
    }

    func playback() -> AsyncStream<[Int16]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(10)) { continuation in
            playbackContinuation = continuation
        }
    }

    func currentSnapshot() -> DirectVoiceSessionSnapshot {
        snapshot
    }

    func start() async {
        guard snapshot.phase == .idle || isFailure(snapshot.phase) else { return }
        updatePhase(.connecting)
        do {
            let identity = try await identityProvider.currentIdentity(now: .now)
            guard let profile = profileStore.load() else {
                throw DirectVoiceSessionFailure.missingServer
            }
            let timestamp = UInt64(Date.now.timeIntervalSince1970)
            let installSuffix: String
            if let installSuffixOverride {
                installSuffix = installSuffixOverride
            } else {
                installSuffix = try await identityProvider.installationSuffix()
            }
            let request = try await authBuilder.makeRequest(
                identity: identity,
                profile: profile,
                installSuffix: installSuffix,
                timestamp: timestamp,
                signer: { [identityProvider] data in
                    try await identityProvider.sign(data)
                }
            )
            try await transport.connect(request)
            let incoming = try await transport.incomingRaw()
            self.identity = identity
            self.profile = profile
            routeArbiter.reset()
            updatePhase(.listening)
            receiveTask = Task { [weak self] in
                do {
                    for try await payload in incoming {
                        guard !Task.isCancelled else { break }
                        await self?.receive(payload)
                    }
                    if !Task.isCancelled { await self?.fail(String(localized: "连接已结束")) }
                } catch {
                    if !Task.isCancelled { await self?.fail(String(localized: "语音连接中断")) }
                }
            }
        } catch {
            await transport.disconnect()
            updatePhase(.failed(message: Self.message(for: error)))
        }
    }

    func stop() async {
        await endTransmit()
        receiveTask?.cancel()
        receiveTask = nil
        receiveIdleTask?.cancel()
        receiveIdleTask = nil
        routeArbiter.reset()
        identity = nil
        profile = nil
        await transport.disconnect()
        updatePhase(.idle)
    }

    func setMuted(_ muted: Bool) {
        snapshot.isMuted = muted
        stateContinuation?.yield(snapshot)
    }

    func beginTransmit() async throws {
        guard case .listening = snapshot.phase,
              let identity, profile != nil,
              !routeArbiter.isOccupied(at: Self.monotonicMilliseconds(), excludingUID: identity.uid) else {
            updatePhase(.busy)
            throw DirectVoiceSessionFailure.channelBusy
        }
        captureBuffer.removeAll(keepingCapacity: true)
        encodedFrames.removeAll(keepingCapacity: true)
        streamBeginUTC = Self.utcMillisecondsLow32()
        updatePhase(.transmitting(startedAt: .now))
        transmitLimitTask?.cancel()
        transmitLimitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await self?.endTransmit()
        }
    }

    func appendCapturedSamples(_ samples: [Int16]) async {
        guard case .transmitting = snapshot.phase else { return }
        captureBuffer.append(contentsOf: samples)
        while captureBuffer.count >= 320 {
            let frame = Array(captureBuffer.prefix(320))
            captureBuffer.removeFirst(320)
            do {
                let encoded = try await codec.encode40ms(frame)
                if !encodedFrames.isEmpty,
                   Self.packetByteCount(frames: encodedFrames + [encoded]) > FMORawHeader.maximumPacketByteCount {
                    try await publishEncodedFrames()
                }
                guard Self.packetByteCount(frames: [encoded]) <= FMORawHeader.maximumPacketByteCount else {
                    throw FMORawError.payloadSize
                }
                encodedFrames.append(encoded)
                if encodedFrames.count >= 5 { try await publishEncodedFrames() }
            } catch {
                await fail(String(localized: "语音编码失败"))
                return
            }
        }
    }

    func endTransmit() async {
        guard case .transmitting = snapshot.phase else {
            transmitLimitTask?.cancel()
            transmitLimitTask = nil
            return
        }
        transmitLimitTask?.cancel()
        transmitLimitTask = nil
        if !captureBuffer.isEmpty {
            let padding = max(0, 320 - captureBuffer.count)
            captureBuffer.append(contentsOf: repeatElement(0, count: padding))
            if let encoded = try? await codec.encode40ms(Array(captureBuffer.prefix(320))) {
                encodedFrames.append(encoded)
            }
        }
        try? await publishEncodedFrames()
        captureBuffer.removeAll(keepingCapacity: true)
        encodedFrames.removeAll(keepingCapacity: true)
        streamBeginUTC = nil
        updatePhase(.listening)
    }

    private func publishEncodedFrames() async throws {
        guard !encodedFrames.isEmpty, let identity, let profile, let streamBeginUTC else { return }
        let payload = try rawEncoder.encode(
            uid: identity.uid,
            callsign: identity.callsign,
            streamBeginUTC: streamBeginUTC,
            timestamp: Self.utcMillisecondsLow32(),
            serverUID: profile.serverUID,
            frames: encodedFrames
        )
        encodedFrames.removeAll(keepingCapacity: true)
        try await transport.publishRaw(payload)
    }

    private func receive(_ payload: Data) async {
        guard let packet = try? rawParser.parse(payload), let identity else { return }
        if packet.header.uid == identity.uid { return }
        let decision = routeArbiter.consider(
            uid: packet.header.uid,
            streamBeginUTC: packet.header.streamBeginUTC,
            nowMilliseconds: Self.monotonicMilliseconds()
        )
        guard decision != .rejected else { return }
        if case .transmitting = snapshot.phase {
            await endTransmit()
            updatePhase(.busy)
            return
        }
        if decision != .continued { try? await codec.reset() }
        snapshot.currentCallsign = packet.header.callsign
        updatePhase(.receiving(callsign: packet.header.callsign))
        for frame in packet.frames where frame.codec == .opus {
            if let samples = try? await codec.decode40ms(frame.payload) {
                if !snapshot.isMuted {
                    playbackContinuation?.yield(samples)
                }
            }
        }
        receiveIdleTask?.cancel()
        receiveIdleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_550))
            guard !Task.isCancelled else { return }
            await self?.finishReceivingIfIdle()
        }
    }

    private func finishReceivingIfIdle() {
        guard case .receiving = snapshot.phase else { return }
        routeArbiter.reset()
        snapshot.currentCallsign = nil
        updatePhase(.listening)
    }

    private func fail(_ message: String) async {
        await endTransmit()
        updatePhase(.failed(message: message))
        await transport.disconnect()
    }

    private func updatePhase(_ phase: DirectVoiceSessionPhase) {
        snapshot.phase = phase
        stateContinuation?.yield(snapshot)
    }

    private func isFailure(_ phase: DirectVoiceSessionPhase) -> Bool {
        if case .failed = phase { return true }
        return false
    }

    private static func utcMillisecondsLow32() -> UInt32 {
        UInt32(truncatingIfNeeded: UInt64(Date.now.timeIntervalSince1970 * 1_000))
    }

    private static func monotonicMilliseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds / 1_000_000
    }

    nonisolated private static func packetByteCount(frames: [Data]) -> Int {
        FMORawHeader.byteCount + frames.reduce(0) { $0 + 16 + $1.count }
    }

    nonisolated private static func message(for error: Error) -> String {
        switch error {
        case DirectVoiceIdentityError.missingIdentity: String(localized: "请先配置 App 身份")
        case DirectVoiceIdentityError.certificateExpired: String(localized: "App 身份已过期")
        case DirectVoiceSessionFailure.missingServer: String(localized: "请先配置语音服务器")
        default: String(localized: "无法连接 FMO 语音服务器")
        }
    }
}

nonisolated enum DirectVoiceSessionFailure: Error, Equatable, Sendable {
    case missingServer
    case channelBusy
}
