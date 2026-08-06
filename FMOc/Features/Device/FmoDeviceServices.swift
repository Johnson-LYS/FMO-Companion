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

nonisolated protocol FmoLocalStatusProviding: Sendable {
    func connect(to endpoint: FmoDeviceEndpoint) async throws
    func getCallsign() async throws -> String
    func getCurrentServer() async throws -> FmoCurrentServer
    func getServerFilter() async throws -> FmoServerFilter
    func getWorkingFrequencyMHz() async throws -> Double
    func getQSOLogCount() async throws -> Int
    func disconnect() async
}

nonisolated protocol FmoStatusRefreshWaiting: Sendable {
    func wait(for interval: Duration) async throws
}

nonisolated struct TaskFmoStatusRefreshWaiter: FmoStatusRefreshWaiting {
    func wait(for interval: Duration) async throws {
        try await Task.sleep(for: interval)
    }
}

nonisolated protocol FmoLocalEventStreaming: Sendable {
    func events(from endpoint: FmoDeviceEndpoint) async -> AsyncThrowingStream<FmoLocalEvent, any Error>
    func disconnect() async
}

nonisolated struct UnavailableFmoLocalStatusProvider: FmoLocalStatusProviding {
    func connect(to endpoint: FmoDeviceEndpoint) throws { throw FmoDeviceError.unsupportedResponse }
    func getCallsign() throws -> String { throw FmoDeviceError.unsupportedResponse }
    func getCurrentServer() throws -> FmoCurrentServer { throw FmoDeviceError.unsupportedResponse }
    func getServerFilter() throws -> FmoServerFilter { throw FmoDeviceError.unsupportedResponse }
    func getWorkingFrequencyMHz() throws -> Double { throw FmoDeviceError.unsupportedResponse }
    func getQSOLogCount() throws -> Int { throw FmoDeviceError.unsupportedResponse }
    func disconnect() {}
}

nonisolated struct UnavailableFmoLocalEventStream: FmoLocalEventStreaming {
    func events(from endpoint: FmoDeviceEndpoint) async -> AsyncThrowingStream<FmoLocalEvent, any Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }

    func disconnect() {}
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
