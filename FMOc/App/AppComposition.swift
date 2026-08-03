import Foundation

enum AppComposition {
    @MainActor
    static func makeDeviceModel(processInfo: ProcessInfo = .processInfo) -> DeviceHomeModel {
#if DEBUG
        if processInfo.environment["FMO_UI_TEST_SCENARIO"] == "local-network-denied" {
            return DeviceHomeModel(
                discovery: LocalNetworkDeniedDiscovery(),
                geoClient: FmoGeoWebSocketClient(),
                locationProvider: CoreLocationProvider(),
                endpointStore: UserDefaultsFmoEndpointStore()
            )
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
#endif
