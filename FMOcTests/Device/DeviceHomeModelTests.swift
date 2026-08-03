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

private nonisolated struct FakeLocationProvider: PhoneLocationProviding {
    let coordinate: GeoCoordinate

    func currentLocation() -> PhoneLocationSample {
        PhoneLocationSample(coordinate: coordinate, horizontalAccuracy: 5, isAccuracyLimited: false)
    }
}

private actor MemoryEndpointStore: FmoEndpointStoring {
    private var endpoint: FmoDeviceEndpoint?
    func load() -> FmoDeviceEndpoint? { endpoint }
    func save(_ endpoint: FmoDeviceEndpoint?) { self.endpoint = endpoint }
}
