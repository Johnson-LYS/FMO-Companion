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
        let modeStore: any LocationSyncModeStoring

#if DEBUG
        switch processInfo.environment["FMO_UI_TEST_SCENARIO"] {
        case "local-network-denied":
            endpointStore = UserDefaultsFmoEndpointStore()
            discovery = LocalNetworkDeniedDiscovery()
        case "saved-device":
            let endpoint = try? FmoDeviceEndpoint(host: "fmo.local", source: .manual)
            endpointStore = UITestEndpointStore(endpoint: endpoint)
            discovery = EmptyDeviceDiscovery()
        case "empty":
            endpointStore = UITestEndpointStore(endpoint: nil)
            discovery = EmptyDeviceDiscovery()
        default:
            endpointStore = UserDefaultsFmoEndpointStore()
            discovery = NWBrowserFmoDeviceDiscovery()
        }
        modeStore = processInfo.environment["FMO_UI_TEST_SCENARIO"] == nil
            ? UserDefaultsLocationSyncModeStore()
            : UITestLocationSyncModeStore()
#else
        endpointStore = UserDefaultsFmoEndpointStore()
        discovery = NWBrowserFmoDeviceDiscovery()
        modeStore = UserDefaultsLocationSyncModeStore()
#endif

        let device = DeviceHomeModel(
            discovery: discovery,
            geoClient: FmoGeoWebSocketClient(),
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
#endif
