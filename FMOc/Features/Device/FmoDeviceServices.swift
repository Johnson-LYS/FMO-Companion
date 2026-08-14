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

nonisolated protocol FmoStationControlling: Sendable {
    func connect(to endpoint: FmoDeviceEndpoint) async throws
    func getServerCatalog() async throws -> FmoDeviceServerCatalog
    func getServerCatalog(
        onUpdate: @escaping @Sendable (FmoDeviceServerCatalog) async -> Void
    ) async throws -> FmoDeviceServerCatalog
    func switchCurrentServer(toUID uid: Int64) async throws -> FmoCurrentServer
    func disconnect() async
}

extension FmoStationControlling {
    func getServerCatalog(
        onUpdate: @escaping @Sendable (FmoDeviceServerCatalog) async -> Void
    ) async throws -> FmoDeviceServerCatalog {
        let catalog = try await getServerCatalog()
        await onUpdate(catalog)
        return catalog
    }
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

nonisolated struct UnavailableFmoStationController: FmoStationControlling {
    func connect(to endpoint: FmoDeviceEndpoint) throws { throw FmoDeviceError.unsupportedResponse }
    func getServerCatalog() throws -> FmoDeviceServerCatalog { throw FmoDeviceError.unsupportedResponse }
    func switchCurrentServer(toUID uid: Int64) throws -> FmoCurrentServer {
        throw FmoDeviceError.unsupportedResponse
    }
    func disconnect() {}
}

nonisolated struct UnavailableFmoLocalEventStream: FmoLocalEventStreaming {
    func events(from endpoint: FmoDeviceEndpoint) async -> AsyncThrowingStream<FmoLocalEvent, any Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }

    func disconnect() {}
}

nonisolated struct FmoEndpointRegistry: Codable, Equatable, Sendable {
    let endpoints: [FmoDeviceEndpoint]
    let lastSuccessfulEndpointID: String?

    init(endpoints: [FmoDeviceEndpoint], lastSuccessfulEndpointID: String?) {
        var seen = Set<String>()
        var uniqueEndpoints = endpoints.filter { seen.insert($0.id).inserted }
        let validLastID = lastSuccessfulEndpointID.flatMap { candidate in
            uniqueEndpoints.contains(where: { $0.id == candidate }) ? candidate : nil
        }

        if let validLastID,
           let index = uniqueEndpoints.firstIndex(where: { $0.id == validLastID }),
           index != uniqueEndpoints.startIndex {
            uniqueEndpoints.insert(uniqueEndpoints.remove(at: index), at: 0)
        }

        self.endpoints = uniqueEndpoints
        self.lastSuccessfulEndpointID = validLastID
    }

    var lastSuccessfulEndpoint: FmoDeviceEndpoint? {
        guard let lastSuccessfulEndpointID else { return nil }
        return endpoints.first { $0.id == lastSuccessfulEndpointID }
    }
}

nonisolated protocol FmoEndpointStoring: Sendable {
    func loadRegistry() async -> FmoEndpointRegistry
    func saveRegistry(_ registry: FmoEndpointRegistry) async
}

extension FmoEndpointStoring {
    func load() async -> FmoDeviceEndpoint? {
        await loadRegistry().lastSuccessfulEndpoint
    }

    func save(_ endpoint: FmoDeviceEndpoint?) async {
        var registry = await loadRegistry()
        guard let endpoint else {
            await saveRegistry(
                FmoEndpointRegistry(
                    endpoints: registry.endpoints,
                    lastSuccessfulEndpointID: nil
                )
            )
            return
        }

        registry = FmoEndpointRegistry(
            endpoints: [endpoint] + registry.endpoints.filter { $0.id != endpoint.id },
            lastSuccessfulEndpointID: endpoint.id
        )
        await saveRegistry(registry)
    }
}

actor UserDefaultsFmoEndpointStore: FmoEndpointStoring {
    private let defaults: UserDefaults
    private let registryKey: String
    private let legacySelectedEndpointKey: String

    init(
        defaults: UserDefaults = .standard,
        registryKey: String = "fmoEndpointRegistry",
        legacySelectedEndpointKey: String = "selectedFmoEndpoint"
    ) {
        self.defaults = defaults
        self.registryKey = registryKey
        self.legacySelectedEndpointKey = legacySelectedEndpointKey
    }

    init(
        suiteName: String,
        registryKey: String = "fmoEndpointRegistry",
        legacySelectedEndpointKey: String = "selectedFmoEndpoint"
    ) {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.registryKey = registryKey
        self.legacySelectedEndpointKey = legacySelectedEndpointKey
    }

    func loadRegistry() -> FmoEndpointRegistry {
        if let data = defaults.data(forKey: registryKey),
           let registry = try? JSONDecoder().decode(FmoEndpointRegistry.self, from: data) {
            return FmoEndpointRegistry(
                endpoints: registry.endpoints,
                lastSuccessfulEndpointID: registry.lastSuccessfulEndpointID
            )
        }

        guard let data = defaults.data(forKey: legacySelectedEndpointKey),
              let endpoint = try? JSONDecoder().decode(FmoDeviceEndpoint.self, from: data) else {
            return FmoEndpointRegistry(endpoints: [], lastSuccessfulEndpointID: nil)
        }
        let migrated = FmoEndpointRegistry(endpoints: [endpoint], lastSuccessfulEndpointID: endpoint.id)
        saveRegistry(migrated)
        return migrated
    }

    func saveRegistry(_ registry: FmoEndpointRegistry) {
        let normalized = FmoEndpointRegistry(
            endpoints: registry.endpoints,
            lastSuccessfulEndpointID: registry.lastSuccessfulEndpointID
        )

        if normalized.endpoints.isEmpty {
            defaults.removeObject(forKey: registryKey)
        } else if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: registryKey)
        }

        guard let endpoint = normalized.lastSuccessfulEndpoint,
              let data = try? JSONEncoder().encode(endpoint) else {
            defaults.removeObject(forKey: legacySelectedEndpointKey)
            return
        }
        defaults.set(data, forKey: legacySelectedEndpointKey)
    }
}
