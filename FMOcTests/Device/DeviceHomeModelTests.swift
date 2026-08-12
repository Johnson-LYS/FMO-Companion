import Foundation
import Testing
@testable import FMOc

@MainActor
struct DeviceHomeModelTests {
    @Test
    func completesDiscoveryConnectLocateAndSyncFlow() async throws {
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .bonjour, name: "FMO")
        let deviceCoordinate = try GeoCoordinate(latitude: 30, longitude: 120)
        let phoneCoordinate = try GeoCoordinate(latitude: 31, longitude: 121)
        let geo = FakeGeoClient(coordinate: deviceCoordinate)
        let status = FakeLocalStatusProvider()
        let store = MemoryEndpointStore()
        let model = DeviceHomeModel(
            discovery: FakeDiscovery(endpoint: endpoint),
            geoClient: geo,
            localStatusProvider: status,
            locationProvider: FakeLocationProvider(coordinate: phoneCoordinate),
            endpointStore: store
        )

        model.startDiscovery()
        await model.waitForDiscovery()
        await model.connect(to: endpoint)
        for _ in 0..<100 where model.dashboardSnapshot.callsign.currentValue == nil {
            await Task.yield()
        }

        #expect(model.phase == .connected)
        #expect(model.endpoints == [endpoint])
        #expect(model.deviceCoordinate == deviceCoordinate)
        #expect(model.dashboardSnapshot.geoLink == .connected)
        #expect(model.dashboardSnapshot.maidenhead.value == "PM00aa")
        #expect(model.dashboardSnapshot.callsign.currentValue == "BG0TST")
        #expect(model.dashboardSnapshot.currentServerName.currentValue == "测试服务器")

        await model.locatePhone()
        #expect(model.phoneLocation?.coordinate == phoneCoordinate)

        await model.syncPhoneCoordinate()
        #expect(model.phase == .success)
        #expect(await geo.lastSetCoordinate() == phoneCoordinate)
        #expect(await store.load() == endpoint)
    }

    @Test
    func keepsLastDerivedGridAsStaleAfterDisconnect() async throws {
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .manual)
        let model = DeviceHomeModel(
            discovery: FakeDiscovery(endpoint: endpoint),
            geoClient: FakeGeoClient(coordinate: try GeoCoordinate(latitude: 31.2304, longitude: 121.4737)),
            locationProvider: FakeLocationProvider(coordinate: try GeoCoordinate(latitude: 31, longitude: 121)),
            endpointStore: MemoryEndpointStore()
        )

        await model.connect(to: endpoint)
        await model.disconnect()

        #expect(model.dashboardSnapshot.geoLink == .disconnected)
        #expect(model.dashboardSnapshot.maidenhead.value == "PM01rf")
        guard case .stale = model.dashboardSnapshot.maidenhead else {
            Issue.record("断开后应保留带过期状态的最后可信网格")
            return
        }
    }

    @Test
    func surfacesTypedConnectionFailure() async throws {
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .manual)
        let model = DeviceHomeModel(
            discovery: FakeDiscovery(endpoint: endpoint),
            geoClient: FailingGeoClient(),
            locationProvider: FakeLocationProvider(coordinate: try GeoCoordinate(latitude: 0, longitude: 0)),
            endpointStore: MemoryEndpointStore()
        )

        await model.connect(to: endpoint)
        #expect(model.phase == .failure)
        #expect(model.issue?.title == String(localized: "无法建立 GEO 连接"))
    }

    @Test
    func offersSettingsRecoveryWhenLocalNetworkIsDenied() async throws {
        let model = DeviceHomeModel(
            discovery: FailingDiscovery(error: .localNetworkDenied),
            geoClient: FailingGeoClient(),
            locationProvider: DeniedLocationProvider(),
            endpointStore: MemoryEndpointStore()
        )

        model.startDiscovery()
        await model.waitForDiscovery()

        #expect(model.phase == .failure)
        #expect(model.issue?.title == String(localized: "本地网络访问已关闭"))
        #expect(model.issue?.recoveryAction == .openSettings)
    }

    @Test
    func keepsDeviceConnectedWhenLocationPermissionIsDenied() async throws {
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .manual)
        let geo = FakeGeoClient(coordinate: try GeoCoordinate(latitude: 30, longitude: 120))
        let model = DeviceHomeModel(
            discovery: FakeDiscovery(endpoint: endpoint),
            geoClient: geo,
            locationProvider: DeniedLocationProvider(),
            endpointStore: MemoryEndpointStore()
        )

        await model.connect(to: endpoint)
        await model.locatePhone()

        #expect(model.phase == .connected)
        #expect(model.isConnected)
        #expect(model.issue?.title == String(localized: "定位访问已关闭"))
        #expect(model.issue?.recoveryAction == .openSettings)
    }

    @Test
    func leavesConnectedStateAfterUnexpectedDisconnect() async throws {
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .manual)
        let phoneCoordinate = try GeoCoordinate(latitude: 31, longitude: 121)
        let geo = DisconnectingGeoClient(
            coordinate: try GeoCoordinate(latitude: 30, longitude: 120)
        )
        let model = DeviceHomeModel(
            discovery: FakeDiscovery(endpoint: endpoint),
            geoClient: geo,
            locationProvider: FakeLocationProvider(coordinate: phoneCoordinate),
            endpointStore: MemoryEndpointStore()
        )

        await model.connect(to: endpoint)
        await model.locatePhone()
        await model.syncPhoneCoordinate()

        #expect(model.phase == .failure)
        #expect(!model.isConnected)
        #expect(model.selectedEndpoint == endpoint)
        #expect(model.issue?.title == String(localized: "FMO 连接已断开"))
        #expect(await geo.disconnectCallCount() == 1)
    }

    @Test
    func discoveryPreservesSavedManualEndpointAndAddsNearbyDevice() async throws {
        let manual = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual)
        let nearby = try FmoDeviceEndpoint(host: "fmo.local", source: .bonjour, name: "FMO")
        let store = MemoryEndpointStore(endpoint: manual)
        let model = DeviceHomeModel(
            discovery: FakeDiscovery(endpoint: nearby),
            geoClient: FakeGeoClient(coordinate: try GeoCoordinate(latitude: 30, longitude: 120)),
            locationProvider: FakeLocationProvider(coordinate: try GeoCoordinate(latitude: 31, longitude: 121)),
            endpointStore: store
        )

        await model.start()
        await model.waitForDiscovery()
        await model.waitForConnection()

        #expect(model.endpoints == [manual, nearby])
        #expect(model.selectedEndpoint == manual)
        #expect(model.isConnected)
        #expect(await store.load() == manual)
    }

    @Test
    func discoveryDoesNotDuplicateManualAndBonjourVersionsOfSameEndpoint() async throws {
        let manual = try FmoDeviceEndpoint(host: "fmo.local", source: .manual)
        let nearby = try FmoDeviceEndpoint(host: "fmo.local", source: .bonjour, name: "FMO")
        let model = DeviceHomeModel(
            discovery: FakeDiscovery(endpoint: nearby),
            geoClient: FakeGeoClient(coordinate: try GeoCoordinate(latitude: 30, longitude: 120)),
            locationProvider: FakeLocationProvider(coordinate: try GeoCoordinate(latitude: 31, longitude: 121)),
            endpointStore: MemoryEndpointStore(endpoint: manual)
        )

        await model.start()
        await model.waitForDiscovery()
        await model.waitForConnection()

        #expect(model.endpoints == [manual])
        #expect(model.selectedEndpoint == manual)
        #expect(model.isConnected)
    }

    @Test
    func failedSavedDeviceFallsThroughToNewlyDiscoveredDevice() async throws {
        let saved = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual, name: "FMO A")
        let nearby = try FmoDeviceEndpoint(host: "192.0.2.11", source: .manual, name: "FMO B")
        let geo = SelectiveGeoClient(
            coordinate: try GeoCoordinate(latitude: 30, longitude: 120),
            failingEndpointIDs: [saved.id]
        )
        let model = DeviceHomeModel(
            discovery: MultipleDeviceDiscovery(endpoints: [nearby]),
            geoClient: geo,
            locationProvider: FakeLocationProvider(coordinate: try GeoCoordinate(latitude: 31, longitude: 121)),
            endpointStore: MemoryEndpointStore(endpoint: saved)
        )

        await model.start()
        await model.waitForDiscovery()
        await model.waitForConnection()

        #expect(model.endpoints == [nearby, saved])
        #expect(model.selectedEndpoint == nearby)
        #expect(model.isConnected)
        #expect(await geo.connectedEndpoints() == [saved, nearby])
    }

    @Test
    func discoveryWithoutSavedDeviceConnectsFirstResultAndOnlyAppendsLaterResults() async throws {
        let first = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual, name: "FMO A")
        let second = try FmoDeviceEndpoint(host: "192.0.2.11", source: .manual, name: "FMO B")
        let geo = CountingGeoClient(coordinate: try GeoCoordinate(latitude: 30, longitude: 120))
        let model = DeviceHomeModel(
            discovery: MultipleDeviceDiscovery(endpoints: [first, second]),
            geoClient: geo,
            locationProvider: FakeLocationProvider(coordinate: try GeoCoordinate(latitude: 31, longitude: 121)),
            endpointStore: MemoryEndpointStore()
        )

        await model.start()
        await model.waitForDiscovery()
        await model.waitForConnection()

        #expect(model.endpoints == [first, second])
        #expect(model.selectedEndpoint == first)
        #expect(model.isConnected)
        #expect(await geo.connectedEndpoints() == [first])
    }

    @Test
    func discoveryWhileConnectedOnlyAddsDevices() async throws {
        let current = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual, name: "FMO A")
        let nearby = try FmoDeviceEndpoint(host: "192.0.2.11", source: .manual, name: "FMO B")
        let geo = CountingGeoClient(coordinate: try GeoCoordinate(latitude: 30, longitude: 120))
        let model = DeviceHomeModel(
            discovery: FakeDiscovery(endpoint: nearby),
            geoClient: geo,
            locationProvider: FakeLocationProvider(coordinate: try GeoCoordinate(latitude: 31, longitude: 121)),
            endpointStore: MemoryEndpointStore()
        )

        await model.connect(to: current)
        model.startDiscovery()
        await model.waitForDiscovery()

        #expect(model.selectedEndpoint == current)
        #expect(model.isConnected)
        #expect(model.endpoints == [current, nearby])
        #expect(await geo.connectedEndpoints() == [current])
    }

    @Test
    func startupTriesSavedDevicesInOrderAndPromotesTheFirstSuccess() async throws {
        let last = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual, name: "FMO A")
        let second = try FmoDeviceEndpoint(host: "192.0.2.11", source: .manual, name: "FMO B")
        let third = try FmoDeviceEndpoint(host: "192.0.2.12", source: .manual, name: "FMO C")
        let store = MemoryEndpointStore(
            endpoints: [second, third, last],
            lastSuccessfulEndpointID: last.id
        )
        let geo = SelectiveGeoClient(
            coordinate: try GeoCoordinate(latitude: 30, longitude: 120),
            failingEndpointIDs: [last.id]
        )
        let model = DeviceHomeModel(
            discovery: MultipleDeviceDiscovery(endpoints: []),
            geoClient: geo,
            locationProvider: FakeLocationProvider(coordinate: try GeoCoordinate(latitude: 31, longitude: 121)),
            endpointStore: store
        )

        await model.start()
        await model.waitForDiscovery()
        await model.waitForConnection()

        #expect(await geo.connectedEndpoints() == [last, second])
        #expect(model.selectedEndpoint == second)
        #expect(model.endpoints == [second, last, third])
        #expect(await store.loadRegistry() == FmoEndpointRegistry(
            endpoints: [second, last, third],
            lastSuccessfulEndpointID: second.id
        ))
    }

    @Test
    func removingCurrentDeviceDoesNotAutomaticallyFailOver() async throws {
        let current = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual, name: "FMO A")
        let other = try FmoDeviceEndpoint(host: "192.0.2.11", source: .manual, name: "FMO B")
        let geo = CountingGeoClient(coordinate: try GeoCoordinate(latitude: 30, longitude: 120))
        let store = MemoryEndpointStore(
            endpoints: [current, other],
            lastSuccessfulEndpointID: current.id
        )
        let model = DeviceHomeModel(
            discovery: MultipleDeviceDiscovery(endpoints: []),
            geoClient: geo,
            locationProvider: FakeLocationProvider(coordinate: try GeoCoordinate(latitude: 31, longitude: 121)),
            endpointStore: store
        )

        await model.start()
        await model.waitForConnection()
        await model.remove(current)

        #expect(model.endpoints == [other])
        #expect(model.selectedEndpoint == nil)
        #expect(!model.isConnected)
        #expect(await geo.connectedEndpoints() == [current])
        #expect(await store.loadRegistry() == FmoEndpointRegistry(
            endpoints: [other],
            lastSuccessfulEndpointID: nil
        ))
    }

    @Test
    func discoveryFailureDoesNotDowngradeAnExistingConnection() async throws {
        let current = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual, name: "FMO A")
        let model = DeviceHomeModel(
            discovery: FailingDiscovery(error: .localNetworkDenied),
            geoClient: FakeGeoClient(coordinate: try GeoCoordinate(latitude: 30, longitude: 120)),
            locationProvider: FakeLocationProvider(coordinate: try GeoCoordinate(latitude: 31, longitude: 121)),
            endpointStore: MemoryEndpointStore()
        )

        await model.connect(to: current)
        model.startDiscovery()
        await model.waitForDiscovery()

        #expect(model.isConnected)
        #expect(model.selectedEndpoint == current)
        #expect(model.issue == nil)
    }

    @Test
    func selectingCurrentDeviceIsIdempotentAndSelectingAnotherSwitches() async throws {
        let first = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual, name: "FMO A")
        let second = try FmoDeviceEndpoint(host: "192.0.2.11", source: .manual, name: "FMO B")
        let geo = CountingGeoClient(coordinate: try GeoCoordinate(latitude: 30, longitude: 120))
        let model = DeviceHomeModel(
            discovery: FakeDiscovery(endpoint: first),
            geoClient: geo,
            locationProvider: FakeLocationProvider(coordinate: try GeoCoordinate(latitude: 31, longitude: 121)),
            endpointStore: MemoryEndpointStore()
        )

        await model.connect(to: first)
        await model.connect(to: first)
        await model.connect(to: second)

        #expect(model.selectedEndpoint == second)
        #expect(model.isConnected)
        #expect(await geo.connectedEndpoints() == [first, second])
    }

    @Test
    func manualSelectionCancelsTheRemainingAutomaticQueue() async throws {
        let saved = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual, name: "FMO A")
        let queued = try FmoDeviceEndpoint(host: "192.0.2.11", source: .manual, name: "FMO B")
        let manual = try FmoDeviceEndpoint(host: "192.0.2.12", source: .manual, name: "FMO C")
        let geo = SuspendingFirstGeoClient(coordinate: try GeoCoordinate(latitude: 30, longitude: 120))
        let model = DeviceHomeModel(
            discovery: MultipleDeviceDiscovery(endpoints: []),
            geoClient: geo,
            locationProvider: FakeLocationProvider(coordinate: try GeoCoordinate(latitude: 31, longitude: 121)),
            endpointStore: MemoryEndpointStore(
                endpoints: [saved, queued],
                lastSuccessfulEndpointID: saved.id
            )
        )

        await model.start()
        for _ in 0..<100 where await geo.connectedEndpoints().isEmpty {
            await Task.yield()
        }
        await model.connect(to: manual)

        #expect(await geo.connectedEndpoints() == [saved, manual])
        #expect(model.selectedEndpoint == manual)
        #expect(model.endpoints == [manual, saved, queued])
        #expect(model.isConnected)
    }

    @Test
    func removingSelectedDeviceDisconnectsAndClearsPersistence() async throws {
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .manual)
        let geo = FakeGeoClient(coordinate: try GeoCoordinate(latitude: 30, longitude: 120))
        let store = MemoryEndpointStore()
        let model = DeviceHomeModel(
            discovery: FakeDiscovery(endpoint: endpoint),
            geoClient: geo,
            locationProvider: FakeLocationProvider(coordinate: try GeoCoordinate(latitude: 31, longitude: 121)),
            endpointStore: store
        )

        model.endpoints = [endpoint]
        await model.connect(to: endpoint)
        await model.remove(endpoint)

        #expect(model.endpoints.isEmpty)
        #expect(model.selectedEndpoint == nil)
        #expect(!model.isConnected)
        #expect(await store.load() == nil)
        #expect(await geo.disconnectCallCount() == 1)
    }

    @Test
    func enrichesConnectedDashboardWithAuthorizedLocalStatus() async throws {
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .manual)
        let status = FakeLocalStatusProvider()
        let model = DeviceHomeModel(
            discovery: FakeDiscovery(endpoint: endpoint),
            geoClient: FakeGeoClient(coordinate: try GeoCoordinate(latitude: 31.2304, longitude: 121.4737)),
            localStatusProvider: status,
            locationProvider: FakeLocationProvider(coordinate: try GeoCoordinate(latitude: 31, longitude: 121)),
            endpointStore: MemoryEndpointStore()
        )

        await model.connect(to: endpoint)

        #expect(model.phase == .connected)
        #expect(model.dashboardSnapshot.geoLink == .connected)
        #expect(model.dashboardSnapshot.localStatusLink == .connected)
        #expect(model.dashboardSnapshot.callsign.currentValue == "BG0TST")
        #expect(model.dashboardSnapshot.currentServerName.currentValue == "测试服务器")
        #expect(model.dashboardSnapshot.filterDistance.currentValue == .kilometers(500))
        #expect(model.dashboardSnapshot.workingFrequencyMHz.currentValue == 438.5)
        #expect(model.dashboardSnapshot.qsoLogCount.currentValue == 18)
        #expect(await status.requestOrder() == ["callsign", "server", "filter", "frequency", "qso"])
    }

    @Test
    func refreshesCurrentServerWhileTheDeviceRemainsConnected() async throws {
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .manual)
        let status = SwitchingLocalStatusProvider()
        let model = DeviceHomeModel(
            discovery: FakeDiscovery(endpoint: endpoint),
            geoClient: FakeGeoClient(coordinate: try GeoCoordinate(latitude: 31.2304, longitude: 121.4737)),
            localStatusProvider: status,
            locationProvider: FakeLocationProvider(coordinate: try GeoCoordinate(latitude: 31, longitude: 121)),
            endpointStore: MemoryEndpointStore(),
            statusRefreshWaiter: SingleImmediateStatusRefreshWaiter()
        )

        await model.connect(to: endpoint)
        for _ in 0..<100 where model.dashboardSnapshot.currentServerName.currentValue != "服务器 B" {
            await Task.yield()
        }

        #expect(model.dashboardSnapshot.currentServerName.currentValue == "服务器 B")
        #expect(await status.currentServerReadCount() >= 2)
        await model.disconnect()
    }
}

struct FmoEndpointStoreTests {
    @Test
    func migratesLegacySelectedEndpointIntoTheRegistry() async throws {
        let suiteName = "FmoEndpointStoreTests.\(UUID().uuidString)"
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .manual)
        try #require(UserDefaults(suiteName: suiteName)).set(
            JSONEncoder().encode(endpoint),
            forKey: "selectedFmoEndpoint"
        )
        let store = UserDefaultsFmoEndpointStore(suiteName: suiteName)

        let registry = await store.loadRegistry()

        #expect(registry == FmoEndpointRegistry(
            endpoints: [endpoint],
            lastSuccessfulEndpointID: endpoint.id
        ))
        #expect(UserDefaults(suiteName: suiteName)?.data(forKey: "fmoEndpointRegistry") != nil)
    }

    @Test
    func registryRoundTripDeduplicatesAndMovesLastSuccessfulFirst() async throws {
        let suiteName = "FmoEndpointStoreTests.\(UUID().uuidString)"
        let first = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual)
        let last = try FmoDeviceEndpoint(host: "192.0.2.11", source: .manual)
        let store = UserDefaultsFmoEndpointStore(suiteName: suiteName)

        await store.saveRegistry(FmoEndpointRegistry(
            endpoints: [first, last, first],
            lastSuccessfulEndpointID: last.id
        ))

        #expect(await store.loadRegistry() == FmoEndpointRegistry(
            endpoints: [last, first],
            lastSuccessfulEndpointID: last.id
        ))
    }
}

private nonisolated struct FakeDiscovery: FmoDeviceDiscovering {
    let endpoint: FmoDeviceEndpoint

    func discover(timeout: Duration) -> AsyncThrowingStream<FmoDeviceEndpoint, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(endpoint)
            continuation.finish()
        }
    }
}

private nonisolated struct MultipleDeviceDiscovery: FmoDeviceDiscovering {
    let endpoints: [FmoDeviceEndpoint]

    func discover(timeout: Duration) -> AsyncThrowingStream<FmoDeviceEndpoint, any Error> {
        AsyncThrowingStream { continuation in
            for endpoint in endpoints {
                continuation.yield(endpoint)
            }
            continuation.finish()
        }
    }
}

private nonisolated struct FailingDiscovery: FmoDeviceDiscovering {
    let error: FmoDeviceError

    func discover(timeout: Duration) -> AsyncThrowingStream<FmoDeviceEndpoint, any Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

private actor FakeGeoClient: FmoGeoClient {
    private var coordinate: GeoCoordinate
    private var setCoordinateValue: GeoCoordinate?
    private var disconnectCalls = 0

    init(coordinate: GeoCoordinate) {
        self.coordinate = coordinate
    }

    func connect(to endpoint: FmoDeviceEndpoint) {}
    func getCoordinate() -> GeoCoordinate { coordinate }
    func setCoordinate(_ coordinate: GeoCoordinate) {
        self.coordinate = coordinate
        setCoordinateValue = coordinate
    }
    func disconnect() { disconnectCalls += 1 }
    func lastSetCoordinate() -> GeoCoordinate? { setCoordinateValue }
    func disconnectCallCount() -> Int { disconnectCalls }
}

private actor CountingGeoClient: FmoGeoClient {
    private let coordinate: GeoCoordinate
    private var endpoints: [FmoDeviceEndpoint] = []

    init(coordinate: GeoCoordinate) {
        self.coordinate = coordinate
    }

    func connect(to endpoint: FmoDeviceEndpoint) {
        endpoints.append(endpoint)
    }
    func getCoordinate() -> GeoCoordinate { coordinate }
    func setCoordinate(_ coordinate: GeoCoordinate) {}
    func disconnect() {}
    func connectedEndpoints() -> [FmoDeviceEndpoint] { endpoints }
}

private actor CountingFailingGeoClient: FmoGeoClient {
    private var endpoints: [FmoDeviceEndpoint] = []

    func connect(to endpoint: FmoDeviceEndpoint) throws {
        endpoints.append(endpoint)
        throw FmoDeviceError.handshakeFailed
    }
    func getCoordinate() throws -> GeoCoordinate { throw FmoDeviceError.disconnected }
    func setCoordinate(_ coordinate: GeoCoordinate) throws { throw FmoDeviceError.disconnected }
    func disconnect() {}
    func connectedEndpoints() -> [FmoDeviceEndpoint] { endpoints }
}

private actor SelectiveGeoClient: FmoGeoClient {
    private let coordinate: GeoCoordinate
    private let failingEndpointIDs: Set<String>
    private var endpoints: [FmoDeviceEndpoint] = []

    init(coordinate: GeoCoordinate, failingEndpointIDs: Set<String>) {
        self.coordinate = coordinate
        self.failingEndpointIDs = failingEndpointIDs
    }

    func connect(to endpoint: FmoDeviceEndpoint) throws {
        endpoints.append(endpoint)
        if failingEndpointIDs.contains(endpoint.id) {
            throw FmoDeviceError.handshakeFailed
        }
    }
    func getCoordinate() -> GeoCoordinate { coordinate }
    func setCoordinate(_ coordinate: GeoCoordinate) {}
    func disconnect() {}
    func connectedEndpoints() -> [FmoDeviceEndpoint] { endpoints }
}

private actor SuspendingFirstGeoClient: FmoGeoClient {
    private let coordinate: GeoCoordinate
    private var endpoints: [FmoDeviceEndpoint] = []

    init(coordinate: GeoCoordinate) {
        self.coordinate = coordinate
    }

    func connect(to endpoint: FmoDeviceEndpoint) async throws {
        endpoints.append(endpoint)
        if endpoints.count == 1 {
            try await Task.sleep(for: .seconds(30))
        }
    }
    func getCoordinate() -> GeoCoordinate { coordinate }
    func setCoordinate(_ coordinate: GeoCoordinate) {}
    func disconnect() {}
    func connectedEndpoints() -> [FmoDeviceEndpoint] { endpoints }
}

private actor FakeLocalStatusProvider: FmoLocalStatusProviding {
    private var requests: [String] = []

    func connect(to endpoint: FmoDeviceEndpoint) {}
    func getCallsign() -> String {
        requests.append("callsign")
        return "BG0TST"
    }
    func getCurrentServer() -> FmoCurrentServer {
        requests.append("server")
        return FmoCurrentServer(uid: 42, name: "测试服务器")
    }
    func getServerFilter() -> FmoServerFilter {
        requests.append("filter")
        return .kilometers(500)
    }
    func getWorkingFrequencyMHz() -> Double {
        requests.append("frequency")
        return 438.5
    }
    func getQSOLogCount() -> Int {
        requests.append("qso")
        return 18
    }
    func disconnect() {}
    func requestOrder() -> [String] { requests }
}

private actor SwitchingLocalStatusProvider: FmoLocalStatusProviding {
    private var serverReads = 0

    func connect(to endpoint: FmoDeviceEndpoint) {}
    func getCallsign() -> String { "BG0TST" }
    func getCurrentServer() -> FmoCurrentServer {
        serverReads += 1
        return FmoCurrentServer(
            uid: Int64(serverReads),
            name: serverReads == 1 ? "服务器 A" : "服务器 B"
        )
    }
    func getServerFilter() -> FmoServerFilter { .kilometers(500) }
    func getWorkingFrequencyMHz() -> Double { 438.5 }
    func getQSOLogCount() -> Int { 18 }
    func disconnect() {}
    func currentServerReadCount() -> Int { serverReads }
}

private actor SingleImmediateStatusRefreshWaiter: FmoStatusRefreshWaiting {
    private var waitCount = 0

    func wait(for interval: Duration) async throws {
        waitCount += 1
        if waitCount == 1 { return }
        try await Task.sleep(for: .seconds(30))
    }
}

private actor FailingGeoClient: FmoGeoClient {
    func connect(to endpoint: FmoDeviceEndpoint) throws { throw FmoDeviceError.handshakeFailed }
    func getCoordinate() throws -> GeoCoordinate { throw FmoDeviceError.disconnected }
    func setCoordinate(_ coordinate: GeoCoordinate) throws { throw FmoDeviceError.disconnected }
    func disconnect() {}
}

private actor DisconnectingGeoClient: FmoGeoClient {
    private let coordinate: GeoCoordinate
    private var disconnectCalls = 0

    init(coordinate: GeoCoordinate) {
        self.coordinate = coordinate
    }

    func connect(to endpoint: FmoDeviceEndpoint) {}
    func getCoordinate() -> GeoCoordinate { coordinate }
    func setCoordinate(_ coordinate: GeoCoordinate) throws { throw FmoDeviceError.disconnected }
    func disconnect() { disconnectCalls += 1 }
    func disconnectCallCount() -> Int { disconnectCalls }
}

private nonisolated struct FakeLocationProvider: PhoneLocationProviding {
    let coordinate: GeoCoordinate

    func currentLocation() -> PhoneLocationSample {
        PhoneLocationSample(coordinate: coordinate, horizontalAccuracy: 5, isAccuracyLimited: false)
    }
}

private nonisolated struct DeniedLocationProvider: PhoneLocationProviding {
    func currentLocation() throws -> PhoneLocationSample { throw PhoneLocationError.denied }
}

private actor MemoryEndpointStore: FmoEndpointStoring {
    private var registry: FmoEndpointRegistry

    init(endpoint: FmoDeviceEndpoint? = nil) {
        registry = FmoEndpointRegistry(
            endpoints: endpoint.map { [$0] } ?? [],
            lastSuccessfulEndpointID: endpoint?.id
        )
    }

    init(endpoints: [FmoDeviceEndpoint], lastSuccessfulEndpointID: String?) {
        registry = FmoEndpointRegistry(
            endpoints: endpoints,
            lastSuccessfulEndpointID: lastSuccessfulEndpointID
        )
    }

    func loadRegistry() -> FmoEndpointRegistry { registry }
    func saveRegistry(_ registry: FmoEndpointRegistry) { self.registry = registry }
}
