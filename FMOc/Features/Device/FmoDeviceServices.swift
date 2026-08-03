import Foundation

nonisolated protocol FmoDeviceDiscovering: Sendable {
    func discover(timeout: Duration) -> AsyncThrowingStream<FmoDeviceEndpoint, any Error>
}

nonisolated protocol FmoGeoClient: Sendable {
    func connect(to endpoint: FmoDeviceEndpoint) async throws
    func getCoordinate() async throws -> GeoCoordinate
    func setCoordinate(_ coordinate: GeoCoordinate) async throws
    func disconnect() async
}

nonisolated protocol FmoEndpointStoring: Sendable {
    func load() async -> FmoDeviceEndpoint?
    func save(_ endpoint: FmoDeviceEndpoint?) async
}

actor UserDefaultsFmoEndpointStore: FmoEndpointStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "selectedFmoEndpoint") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> FmoDeviceEndpoint? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FmoDeviceEndpoint.self, from: data)
    }

    func save(_ endpoint: FmoDeviceEndpoint?) {
        guard let endpoint, let data = try? JSONEncoder().encode(endpoint) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
