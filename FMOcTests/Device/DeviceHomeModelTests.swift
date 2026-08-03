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
        let store = MemoryEndpointStore()
        let model = DeviceHomeModel(
            discovery: FakeDiscovery(endpoint: endpoint),
            geoClient: geo,
            locationProvider: FakeLocationProvider(coordinate: phoneCoordinate),
            endpointStore: store
        )

        await model.discover()
        #expect(model.phase == .found)
        #expect(model.endpoints == [endpoint])

        await model.connect(to: endpoint)
        #expect(model.phase == .connected)
        #expect(model.deviceCoordinate == deviceCoordinate)

        await model.locatePhone()
        #expect(model.phoneLocation?.coordinate == phoneCoordinate)

        await model.syncPhoneCoordinate()
        #expect(model.phase == .success)
        #expect(await geo.lastSetCoordinate() == phoneCoordinate)
        #expect(await store.load() == endpoint)
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
        #expect(model.issue?.title == "无法建立 GEO 连接")
    }

    @Test
    func offersSettingsRecoveryWhenLocalNetworkIsDenied() async throws {
        let model = DeviceHomeModel(
            discovery: FailingDiscovery(error: .localNetworkDenied),
            geoClient: FailingGeoClient(),
            locationProvider: DeniedLocationProvider(),
            endpointStore: MemoryEndpointStore()
        )

        await model.discover()

        #expect(model.phase == .failure)
        #expect(model.issue?.title == "本地网络访问已关闭")
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
        #expect(model.issue?.title == "定位访问已关闭")
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
        #expect(model.issue?.title == "FMO 连接已断开")
        #expect(await geo.disconnectCallCount() == 1)
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

    init(coordinate: GeoCoordinate) {
        self.coordinate = coordinate
    }

    func connect(to endpoint: FmoDeviceEndpoint) {}
    func getCoordinate() -> GeoCoordinate { coordinate }
    func setCoordinate(_ coordinate: GeoCoordinate) {
        self.coordinate = coordinate
        setCoordinateValue = coordinate
    }
    func disconnect() {}
    func lastSetCoordinate() -> GeoCoordinate? { setCoordinateValue }
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
    private var endpoint: FmoDeviceEndpoint?
    func load() -> FmoDeviceEndpoint? { endpoint }
    func save(_ endpoint: FmoDeviceEndpoint?) { self.endpoint = endpoint }
}
