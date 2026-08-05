import Foundation

enum AppComposition {
    @MainActor
    struct Models {
        let device: DeviceHomeModel
        let locationAutomation: LocationAutomationModel
        let officialWeb: OfficialWebModel
    }

    @MainActor
    static func makeModels(processInfo: ProcessInfo = .processInfo) -> Models {
        let endpointStore: any FmoEndpointStoring
        let discovery: any FmoDeviceDiscovering
        let geoClient: any FmoGeoClient
        let modeStore: any LocationSyncModeStoring

#if DEBUG
        switch processInfo.environment["FMO_UI_TEST_SCENARIO"] {
        case "local-network-denied":
            endpointStore = UserDefaultsFmoEndpointStore()
            discovery = LocalNetworkDeniedDiscovery()
            geoClient = FmoGeoWebSocketClient()
        case "saved-device":
            let endpoint = try? FmoDeviceEndpoint(host: "fmo.local", source: .manual)
            endpointStore = UITestEndpointStore(endpoint: endpoint)
            discovery = EmptyDeviceDiscovery()
            geoClient = FmoGeoWebSocketClient()
        case "dashboard-connected":
            let endpoint = try? FmoDeviceEndpoint(host: "fmo.local", source: .manual)
            endpointStore = UITestEndpointStore(endpoint: endpoint)
            discovery = EmptyDeviceDiscovery()
            geoClient = UITestGeoClient()
        case "empty":
            endpointStore = UITestEndpointStore(endpoint: nil)
            discovery = EmptyDeviceDiscovery()
            geoClient = FmoGeoWebSocketClient()
        default:
            endpointStore = UserDefaultsFmoEndpointStore()
            discovery = NWBrowserFmoDeviceDiscovery()
            geoClient = FmoGeoWebSocketClient()
        }
        modeStore = processInfo.environment["FMO_UI_TEST_SCENARIO"] == nil
            ? UserDefaultsLocationSyncModeStore()
            : UITestLocationSyncModeStore()
#else
        endpointStore = UserDefaultsFmoEndpointStore()
        discovery = NWBrowserFmoDeviceDiscovery()
        geoClient = FmoGeoWebSocketClient()
        modeStore = UserDefaultsLocationSyncModeStore()
#endif

        let device = DeviceHomeModel(
            discovery: discovery,
            geoClient: geoClient,
            locationProvider: CoreLocationProvider(),
            endpointStore: endpointStore
        )
        let coordinator = AutomaticLocationSyncCoordinator(
            locationProvider: CoreLocationAutomaticProvider(),
            networkObserver: NWPathNetworkObserver(),
            geoClient: FmoGeoWebSocketClient(),
            endpointStore: endpointStore,
            modeStore: modeStore
        )
        let locationAutomation = LocationAutomationModel(
            coordinator: coordinator,
            authorizationReader: CoreLocationAuthorizationReader()
        )

        return Models(
            device: device,
            locationAutomation: locationAutomation,
            officialWeb: OfficialWebModel()
        )
    }

    @MainActor
    static func makeDeviceModel(processInfo: ProcessInfo = .processInfo) -> DeviceHomeModel {
        makeModels(processInfo: processInfo).device
    }
}

#if DEBUG
private nonisolated struct LocalNetworkDeniedDiscovery: FmoDeviceDiscovering {
    func discover(timeout: Duration) -> AsyncThrowingStream<FmoDeviceEndpoint, any Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: FmoDeviceError.localNetworkDenied)
        }
    }
}

private nonisolated struct EmptyDeviceDiscovery: FmoDeviceDiscovering {
    func discover(timeout: Duration) -> AsyncThrowingStream<FmoDeviceEndpoint, any Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private actor UITestEndpointStore: FmoEndpointStoring {
    private var endpoint: FmoDeviceEndpoint?

    init(endpoint: FmoDeviceEndpoint?) {
        self.endpoint = endpoint
    }

    func load() -> FmoDeviceEndpoint? { endpoint }
    func save(_ endpoint: FmoDeviceEndpoint?) { self.endpoint = endpoint }
}

private actor UITestLocationSyncModeStore: LocationSyncModeStoring {
    private var mode = LocationSyncMode.manual

    func load() -> LocationSyncMode { mode }
    func save(_ mode: LocationSyncMode) { self.mode = mode }
}

private actor UITestGeoClient: FmoGeoClient {
    func connect(to endpoint: FmoDeviceEndpoint) {}
    func getCoordinate() throws -> GeoCoordinate {
        try GeoCoordinate(latitude: 31.2304, longitude: 121.4737)
    }
    func setCoordinate(_ coordinate: GeoCoordinate) {}
    func disconnect() {}
}
#endif
