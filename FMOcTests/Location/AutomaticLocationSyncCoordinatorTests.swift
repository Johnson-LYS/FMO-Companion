import Foundation
import Testing
@testable import FMOc

struct AutomaticLocationSyncCoordinatorTests {
    @Test
    func offlineDefersSendingAndRecoverySendsLatestSample() async throws {
        let fixture = try Fixture()
        await fixture.coordinator.start(mode: .lowPower)
        fixture.network.send(.unavailable)
        await fixture.location.send(.location(sample(at: 1_000)))

        #expect(await eventually {
            await fixture.coordinator.currentSnapshot().phase == .paused(.networkUnavailable)
        })
        #expect(await fixture.geo.setCallCount() == 0)

        fixture.network.send(.available)

        #expect(await eventually { await fixture.geo.setCallCount() == 1 })
        let snapshot = await fixture.coordinator.currentSnapshot()
        #expect(snapshot.lastAttempt?.result == .success)
        #expect(snapshot.lastSuccessAt != nil)
    }

    @Test
    func successfulSyncAdvancesCheckpointAndThrottlesNextSample() async throws {
        let fixture = try Fixture()
        await fixture.coordinator.start(mode: .lowPower)
        fixture.network.send(.available)
        await fixture.location.send(.location(sample(at: 1_000)))
        #expect(await eventually { await fixture.geo.setCallCount() == 1 })

        await fixture.location.send(.location(sample(at: 1_100)))
        await fixture.location.send(.location(sample(at: 1_900)))

        #expect(await eventually { await fixture.geo.setCallCount() == 2 })
        #expect(await fixture.geo.setCallCount() == 2)
    }

    @Test
    func connectionFailuresUseBackoffThenRecover() async throws {
        let waiter = RecordingRetryWaiter()
        let fixture = try Fixture(failuresBeforeSuccess: 2, waiter: waiter)
        await fixture.coordinator.start(mode: .vehicle)
        fixture.network.send(.available)
        await fixture.location.send(.location(sample(at: 1_000)))

        #expect(await eventually { await fixture.geo.setCallCount() == 1 })
        #expect(await waiter.recordedDelays() == [.seconds(1), .seconds(2)])
        #expect(await fixture.coordinator.currentSnapshot().lastAttempt?.result == .success)
    }

    @Test
    func missingDevicePausesWithoutRetrying() async throws {
        let fixture = Fixture(endpoint: nil)
        await fixture.coordinator.start(mode: .lowPower)
        fixture.network.send(.available)
        await fixture.location.send(.location(sample(at: 1_000)))

        #expect(await eventually {
            await fixture.coordinator.currentSnapshot().phase == .paused(.noDevice)
        })
        #expect(await fixture.geo.connectCallCount() == 0)
    }

    @Test
    func stopCancelsRuntimeAndPersistsManualMode() async throws {
        let fixture = try Fixture()
        await fixture.coordinator.start(mode: .vehicle)

        await fixture.coordinator.stop()

        let snapshot = await fixture.coordinator.currentSnapshot()
        #expect(snapshot.mode == .manual)
        #expect(snapshot.phase == .stopped)
        #expect(await fixture.modeStore.load() == .manual)
        #expect(await fixture.location.stopCallCount() >= 2)
        #expect(await fixture.geo.disconnectCallCount() >= 2)
    }

    @Test
    func backoffPolicyCapsAtSixtySeconds() {
        #expect(LocationSyncBackoffPolicy.default.delay(forRetry: -1) == .seconds(1))
        #expect(LocationSyncBackoffPolicy.default.delay(forRetry: 0) == .seconds(1))
        #expect(LocationSyncBackoffPolicy.default.delay(forRetry: 1) == .seconds(2))
        #expect(LocationSyncBackoffPolicy.default.delay(forRetry: 6) == .seconds(60))
        #expect(LocationSyncBackoffPolicy.default.delay(forRetry: 100) == .seconds(60))
    }

    private func sample(at timestamp: TimeInterval) -> AutomaticLocationSample {
        AutomaticLocationSample(
            syncSample: LocationSyncSample(
                coordinate: try! GeoCoordinate(latitude: 30, longitude: 120),
                timestamp: Date(timeIntervalSince1970: timestamp)
            ),
            horizontalAccuracy: 5,
            isAccuracyLimited: false
        )
    }

    private func eventually(
        _ condition: () async -> Bool
    ) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
}

private struct Fixture {
    let location: ControllableAutomaticLocationProvider
    let network: ControllableNetworkObserver
    let geo: RecordingGeoClient
    let endpointStore: MemoryAutomaticEndpointStore
    let modeStore: MemoryLocationSyncModeStore
    let coordinator: AutomaticLocationSyncCoordinator

    init(
        failuresBeforeSuccess: Int = 0,
        waiter: any RetryWaiting = ImmediateRetryWaiter()
    ) throws {
        self.init(
            endpoint: try FmoDeviceEndpoint(
                host: "fmo.local",
                source: .manual
            ),
            failuresBeforeSuccess: failuresBeforeSuccess,
            waiter: waiter
        )
    }

    init(
        endpoint: FmoDeviceEndpoint?,
        failuresBeforeSuccess: Int = 0,
        waiter: any RetryWaiting = ImmediateRetryWaiter()
    ) {
        let location = ControllableAutomaticLocationProvider()
        let network = ControllableNetworkObserver()
        let geo = RecordingGeoClient(failuresBeforeSuccess: failuresBeforeSuccess)
        let endpointStore = MemoryAutomaticEndpointStore(endpoint: endpoint)
        let modeStore = MemoryLocationSyncModeStore()
        self.location = location
        self.network = network
        self.geo = geo
        self.endpointStore = endpointStore
        self.modeStore = modeStore
        coordinator = AutomaticLocationSyncCoordinator(
            locationProvider: location,
            networkObserver: network,
            geoClient: geo,
            endpointStore: endpointStore,
            modeStore: modeStore,
            waiter: waiter,
            dateProvider: FixedDateProvider(date: Date(timeIntervalSince1970: 5_000))
        )
    }
}

private actor ControllableAutomaticLocationProvider: AutomaticLocationProviding {
    private var continuation: AsyncThrowingStream<
        AutomaticLocationEvent,
        any Error
    >.Continuation?
    private var stopCalls = 0

    init() {}

    func updates(
        for mode: LocationSyncMode
    ) -> AsyncThrowingStream<AutomaticLocationEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream<
            AutomaticLocationEvent,
            any Error
        >.makeStream()
        self.continuation = continuation
        return stream
    }

    func send(_ event: AutomaticLocationEvent) {
        continuation?.yield(event)
    }

    func stop() {
        stopCalls += 1
        continuation?.finish()
        continuation = nil
    }

    func stopCallCount() -> Int { stopCalls }
}

private nonisolated final class ControllableNetworkObserver: NetworkPathObserving, @unchecked Sendable {
    private let stream: AsyncStream<NetworkPathState>
    private let continuation: AsyncStream<NetworkPathState>.Continuation

    init() {
        let (stream, continuation) = AsyncStream<NetworkPathState>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    func updates() -> AsyncStream<NetworkPathState> { stream }
    func send(_ state: NetworkPathState) { continuation.yield(state) }
}

private actor RecordingGeoClient: FmoGeoClient {
    private var failuresBeforeSuccess: Int
    private var connectCalls = 0
    private var setCalls = 0
    private var disconnectCalls = 0

    init(failuresBeforeSuccess: Int) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func connect(to endpoint: FmoDeviceEndpoint) throws {
        connectCalls += 1
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw FmoDeviceError.handshakeFailed
        }
    }

    func getCoordinate() throws -> GeoCoordinate {
        throw FmoDeviceError.unsupportedResponse
    }

    func setCoordinate(_ coordinate: GeoCoordinate) {
        setCalls += 1
    }

    func disconnect() {
        disconnectCalls += 1
    }

    func connectCallCount() -> Int { connectCalls }
    func setCallCount() -> Int { setCalls }
    func disconnectCallCount() -> Int { disconnectCalls }
}

private actor MemoryAutomaticEndpointStore: FmoEndpointStoring {
    private var endpoint: FmoDeviceEndpoint?

    init(endpoint: FmoDeviceEndpoint?) {
        self.endpoint = endpoint
    }

    func load() -> FmoDeviceEndpoint? { endpoint }
    func save(_ endpoint: FmoDeviceEndpoint?) { self.endpoint = endpoint }
}

private actor MemoryLocationSyncModeStore: LocationSyncModeStoring {
    private var mode: LocationSyncMode = .manual

    init() {}

    func load() -> LocationSyncMode { mode }
    func save(_ mode: LocationSyncMode) { self.mode = mode }
}

private actor RecordingRetryWaiter: RetryWaiting {
    private var delays: [Duration] = []

    init() {}

    func wait(for delay: Duration) {
        delays.append(delay)
    }

    func recordedDelays() -> [Duration] { delays }
}

private nonisolated struct ImmediateRetryWaiter: RetryWaiting {
    func wait(for delay: Duration) async throws {}
}

private nonisolated struct FixedDateProvider: DateProviding {
    let date: Date

    func now() -> Date { date }
}
