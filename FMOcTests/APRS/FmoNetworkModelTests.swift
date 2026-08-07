import Foundation
import Testing
@testable import FMOc

@MainActor
struct FmoNetworkModelTests {
    @Test
    func restoresIdentityAndPublishesReadySession() async throws {
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "BG0TST", ssid: 10)
        let store = MemoryAPRSIdentityStore(
            configuration: ReceiveOnlyAPRSIdentityConfiguration(
                identity: identity,
                source: .manual
            )
        )
        let receiver = ModelTestAPRSReceiver(mode: .readyAndWait)
        let sut = makeModel(receiver: receiver, store: store)

        await sut.restoreIfNeeded(isActive: true)

        #expect(await eventually { sut.phase == .receiving })
        #expect(sut.identity == identity)
        #expect(sut.serverCallsign == "T2TEST")
        let requestedIdentities = await receiver.requestedIdentities()
        #expect(requestedIdentities == [identity])
        await sut.setActive(false)
    }

    @Test
    func savingManualIdentityNormalizesPersistsAndConnects() async throws {
        let store = MemoryAPRSIdentityStore(configuration: nil)
        let receiver = ModelTestAPRSReceiver(mode: .readyAndWait)
        let sut = makeModel(receiver: receiver, store: store)
        await sut.restoreIfNeeded(isActive: true)
        #expect(sut.phase == .unconfigured)

        let issue = await sut.saveManualIdentity(callsign: " bg0tst ", ssid: 10)

        #expect(issue == nil)
        #expect(await eventually { sut.phase == .receiving })
        #expect(sut.identity?.loginCallsign == "BG0TST-10")
        let restored = await store.load()
        #expect(restored?.source == .manual)
        await sut.setActive(false)
    }

    @Test
    func trustedFMOCallsignDoesNotReplaceManualIdentity() async throws {
        let store = MemoryAPRSIdentityStore(configuration: nil)
        let receiver = ModelTestAPRSReceiver(mode: .readyAndWait)
        let sut = makeModel(receiver: receiver, store: store)
        await sut.restoreIfNeeded(isActive: true)
        _ = await sut.saveManualIdentity(callsign: "BG0OWN", ssid: 12)

        await sut.adoptTrustedFMOCallsign("BG0BOX")

        #expect(sut.identity?.loginCallsign == "BG0OWN-12")
        let restored = await store.load()
        #expect(restored?.identity.loginCallsign == "BG0OWN-12")
        await sut.setActive(false)
    }

    @Test
    func inactiveSessionPausesAndActiveSessionReconnects() async throws {
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "BG0TST", ssid: 10)
        let store = MemoryAPRSIdentityStore(
            configuration: ReceiveOnlyAPRSIdentityConfiguration(
                identity: identity,
                source: .inherited
            )
        )
        let receiver = ModelTestAPRSReceiver(mode: .readyAndWait)
        let sut = makeModel(receiver: receiver, store: store)
        await sut.restoreIfNeeded(isActive: true)
        #expect(await eventually { sut.phase == .receiving })

        await sut.setActive(false)
        #expect(sut.phase == .paused)

        await sut.setActive(true)
        let reconnected = await eventually {
            let requested = await receiver.requestedIdentities()
            return sut.phase == .receiving && requested.count == 2
        }
        #expect(reconnected)
        await sut.setActive(false)
    }

    @Test
    func endedConnectionMovesToWaitingStateBeforeRetry() async throws {
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "BG0TST", ssid: 10)
        let store = MemoryAPRSIdentityStore(
            configuration: ReceiveOnlyAPRSIdentityConfiguration(
                identity: identity,
                source: .manual
            )
        )
        let receiver = ModelTestAPRSReceiver(mode: .finishImmediately)
        let sut = makeModel(receiver: receiver, store: store)

        await sut.restoreIfNeeded(isActive: true)

        #expect(await eventually { sut.phase == .waitingToRetry })
        await sut.setActive(false)
    }

    @Test
    func loginTimeoutDisconnectsStalledSession() async throws {
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "BG0TST", ssid: 10)
        let store = MemoryAPRSIdentityStore(
            configuration: ReceiveOnlyAPRSIdentityConfiguration(
                identity: identity,
                source: .manual
            )
        )
        let receiver = ModelTestAPRSReceiver(mode: .waitWithoutReady)
        let sut = makeModel(
            receiver: receiver,
            store: store,
            loginTimeout: .milliseconds(10)
        )

        await sut.restoreIfNeeded(isActive: true)

        #expect(await eventually { sut.phase == .waitingToRetry })
        #expect(await eventually { await receiver.disconnectCount() >= 2 })
        await sut.setActive(false)
    }

    private func makeModel(
        receiver: ModelTestAPRSReceiver,
        store: MemoryAPRSIdentityStore,
        loginTimeout: Duration = .seconds(30)
    ) -> FmoNetworkModel {
        FmoNetworkModel(
            receiver: receiver,
            identityStore: store,
            policy: FmoNetworkModel.Policy(
                loginTimeout: loginTimeout,
                retryDelays: [.seconds(30)]
            )
        )
    }

    private func eventually(
        _ condition: () async -> Bool,
        attempts: Int = 100
    ) async -> Bool {
        for _ in 0 ..< attempts {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

private actor MemoryAPRSIdentityStore: ReceiveOnlyAPRSIdentityStoring {
    private var configuration: ReceiveOnlyAPRSIdentityConfiguration?

    init(configuration: ReceiveOnlyAPRSIdentityConfiguration?) {
        self.configuration = configuration
    }

    func load() -> ReceiveOnlyAPRSIdentityConfiguration? { configuration }

    func saveManual(_ identity: ReceiveOnlyAPRSIdentity) {
        configuration = ReceiveOnlyAPRSIdentityConfiguration(
            identity: identity,
            source: .manual
        )
    }

    func adoptInherited(_ identity: ReceiveOnlyAPRSIdentity) {
        guard configuration?.source != .manual else { return }
        configuration = ReceiveOnlyAPRSIdentityConfiguration(
            identity: identity,
            source: .inherited
        )
    }
}

private actor ModelTestAPRSReceiver: APRSISReceiving {
    enum Mode {
        case readyAndWait
        case finishImmediately
        case waitWithoutReady
    }

    private let mode: Mode
    private var identities: [ReceiveOnlyAPRSIdentity] = []
    private var continuation: AsyncThrowingStream<APRSISInboundEvent, any Error>.Continuation?
    private var disconnects = 0

    init(mode: Mode) {
        self.mode = mode
    }

    func events(
        identity: ReceiveOnlyAPRSIdentity,
        endpoint: APRSISEndpoint
    ) -> AsyncThrowingStream<APRSISInboundEvent, any Error> {
        identities.append(identity)
        return AsyncThrowingStream { continuation in
            switch mode {
            case .readyAndWait:
                self.continuation = continuation
                continuation.yield(.sessionReady(serverCallsign: "T2TEST"))
            case .finishImmediately:
                continuation.finish()
            case .waitWithoutReady:
                self.continuation = continuation
            }
        }
    }

    func disconnect() {
        disconnects += 1
        continuation?.finish()
        continuation = nil
    }

    func requestedIdentities() -> [ReceiveOnlyAPRSIdentity] { identities }
    func disconnectCount() -> Int { disconnects }
}
