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
        let localStatusProvider: any FmoLocalStatusProviding
        let localEventStream: any FmoLocalEventStreaming
        let modeStore: any LocationSyncModeStoring

#if DEBUG
        switch processInfo.environment["FMO_UI_TEST_SCENARIO"] {
        case "local-network-denied":
            endpointStore = UserDefaultsFmoEndpointStore()
            discovery = LocalNetworkDeniedDiscovery()
            geoClient = FmoGeoWebSocketClient()
            localStatusProvider = FmoLocalStatusWebSocketClient()
            localEventStream = FmoLocalEventWebSocketClient()
        case "saved-device":
            let endpoint = try? FmoDeviceEndpoint(host: "fmo.local", source: .manual)
            endpointStore = UITestEndpointStore(endpoint: endpoint)
            discovery = EmptyDeviceDiscovery()
            geoClient = FmoGeoWebSocketClient()
            localStatusProvider = FmoLocalStatusWebSocketClient()
            localEventStream = FmoLocalEventWebSocketClient()
        case "dashboard-connected":
            let endpoint = try? FmoDeviceEndpoint(host: "fmo.local", source: .manual)
            endpointStore = UITestEndpointStore(endpoint: endpoint)
            discovery = EmptyDeviceDiscovery()
            geoClient = UITestGeoClient()
            localStatusProvider = UITestLocalStatusProvider()
            localEventStream = UITestLocalEventStream()
        case "automatic-connection":
            let endpoint = try? FmoDeviceEndpoint(host: "fmo.local", source: .manual)
            endpointStore = UITestEndpointStore(endpoint: nil)
            discovery = endpoint.map(UITestSingleDeviceDiscovery.init(endpoint:)) ?? EmptyDeviceDiscovery()
            geoClient = UITestGeoClient()
            localStatusProvider = UITestLocalStatusProvider()
            localEventStream = UITestLocalEventStream()
        case "empty":
            endpointStore = UITestEndpointStore(endpoint: nil)
            discovery = EmptyDeviceDiscovery()
            geoClient = FmoGeoWebSocketClient()
            localStatusProvider = FmoLocalStatusWebSocketClient()
            localEventStream = FmoLocalEventWebSocketClient()
        default:
            endpointStore = UserDefaultsFmoEndpointStore()
            discovery = NWBrowserFmoDeviceDiscovery()
            geoClient = FmoGeoWebSocketClient()
            localStatusProvider = FmoLocalStatusWebSocketClient()
            localEventStream = FmoLocalEventWebSocketClient()
        }
        modeStore = processInfo.environment["FMO_UI_TEST_SCENARIO"] == nil
            ? UserDefaultsLocationSyncModeStore()
            : UITestLocationSyncModeStore()
#else
        endpointStore = UserDefaultsFmoEndpointStore()
        discovery = NWBrowserFmoDeviceDiscovery()
        geoClient = FmoGeoWebSocketClient()
        localStatusProvider = FmoLocalStatusWebSocketClient()
        localEventStream = FmoLocalEventWebSocketClient()
        modeStore = UserDefaultsLocationSyncModeStore()
#endif

        let device = DeviceHomeModel(
            discovery: discovery,
            geoClient: geoClient,
            localStatusProvider: localStatusProvider,
            localEventStream: localEventStream,
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

private nonisolated struct UITestSingleDeviceDiscovery: FmoDeviceDiscovering {
    let endpoint: FmoDeviceEndpoint

    func discover(timeout: Duration) -> AsyncThrowingStream<FmoDeviceEndpoint, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(endpoint)
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

private actor UITestLocalStatusProvider: FmoLocalStatusProviding {
    func connect(to endpoint: FmoDeviceEndpoint) {}
    func getCallsign() -> String { "BG0TST" }
    func getCurrentServer() -> FmoCurrentServer { FmoCurrentServer(uid: 42, name: "测试服务器") }
    func getServerFilter() -> FmoServerFilter { .kilometers(500) }
    func getWorkingFrequencyMHz() -> Double { 438.5 }
    func getQSOLogCount() -> Int { 18 }
    func disconnect() {}
}

private nonisolated struct UITestLocalEventStream: FmoLocalEventStreaming {
    func events(from endpoint: FmoDeviceEndpoint) async -> AsyncThrowingStream<FmoLocalEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                .history([
                    FmoRecentLocalActivity(
                        callsign: "BG1ABC",
                        occurredAt: Date(timeIntervalSince1970: 1_700_000_000)
                    )
                ])
            )
            continuation.yield(
                .speaking(
                    FmoSpeakingState(
                        callsign: "BG1ABC",
                        grid: "OM20xx",
                        isSpeaking: true,
                        sequence: 1,
                        deviceUptimeMilliseconds: 10
                    )
                )
            )
        }
    }

    func disconnect() {}
}
#endif
