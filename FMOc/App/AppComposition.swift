import Foundation

enum AppComposition {
    @MainActor
    static func makeDeviceModel(processInfo: ProcessInfo = .processInfo) -> DeviceHomeModel {
#if DEBUG
        switch processInfo.environment["FMO_UI_TEST_SCENARIO"] {
        case "local-network-denied":
            return DeviceHomeModel(
                discovery: LocalNetworkDeniedDiscovery(),
                geoClient: FmoGeoWebSocketClient(),
                locationProvider: CoreLocationProvider(),
                endpointStore: UserDefaultsFmoEndpointStore()
            )
        case "saved-device":
            let endpoint = try? FmoDeviceEndpoint(host: "fmo.local", source: .manual)
            return DeviceHomeModel(
                discovery: EmptyDeviceDiscovery(),
                geoClient: FmoGeoWebSocketClient(),
                locationProvider: CoreLocationProvider(),
                endpointStore: UITestEndpointStore(endpoint: endpoint)
            )
        default:
            break
        }
#endif
        return .live()
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
#endif
