import Testing
@testable import FMOc

struct FmoConnectionDiagnoserTests {
    @Test
    func reportsAllStepsInDependencyOrder() async throws {
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .manual)
        let diagnoser = FmoConnectionDiagnoser(
            localNetwork: StubLocalNetworkChecker(),
            endpoint: StubEndpointChecker(port: 80),
            http: StubHTTPChecker(statusCode: 200),
            geo: StubGeoChecker()
        )

        let updates = await collect(diagnoser.diagnose(endpoint))

        #expect(updates == [
            FmoDiagnosticUpdate(step: .localNetwork, state: .running),
            FmoDiagnosticUpdate(step: .localNetwork, state: .passed(.wifiAvailable)),
            FmoDiagnosticUpdate(step: .endpoint, state: .running),
            FmoDiagnosticUpdate(step: .endpoint, state: .passed(.endpointReachable(port: 80))),
            FmoDiagnosticUpdate(step: .http, state: .running),
            FmoDiagnosticUpdate(step: .http, state: .passed(.httpResponse(statusCode: 200))),
            FmoDiagnosticUpdate(step: .geo, state: .running),
            FmoDiagnosticUpdate(step: .geo, state: .passed(.geoResponse)),
        ])
    }

    @Test
    func stopsAfterFailureAndSkipsDependentSteps() async throws {
        let endpoint = try FmoDeviceEndpoint(host: "missing.local", source: .manual)
        let diagnoser = FmoConnectionDiagnoser(
            localNetwork: StubLocalNetworkChecker(),
            endpoint: StubEndpointChecker(failure: .resolutionFailed),
            http: StubHTTPChecker(statusCode: 200),
            geo: StubGeoChecker()
        )

        let updates = await collect(diagnoser.diagnose(endpoint))

        #expect(updates == [
            FmoDiagnosticUpdate(step: .localNetwork, state: .running),
            FmoDiagnosticUpdate(step: .localNetwork, state: .passed(.wifiAvailable)),
            FmoDiagnosticUpdate(step: .endpoint, state: .running),
            FmoDiagnosticUpdate(step: .endpoint, state: .failed(.resolutionFailed)),
            FmoDiagnosticUpdate(step: .http, state: .skipped),
            FmoDiagnosticUpdate(step: .geo, state: .skipped),
        ])
    }

    private func collect(
        _ stream: AsyncStream<FmoDiagnosticUpdate>
    ) async -> [FmoDiagnosticUpdate] {
        var updates: [FmoDiagnosticUpdate] = []
        for await update in stream { updates.append(update) }
        return updates
    }
}

private nonisolated struct StubLocalNetworkChecker: FmoLocalNetworkChecking {
    func check() async throws {}
}

private nonisolated struct StubEndpointChecker: FmoEndpointChecking {
    let port: Int
    let failure: FmoDiagnosticFailure?

    init(port: Int = 80, failure: FmoDiagnosticFailure? = nil) {
        self.port = port
        self.failure = failure
    }

    func check(_ endpoint: FmoDeviceEndpoint) async throws -> Int {
        if let failure { throw failure }
        return port
    }
}

private nonisolated struct StubHTTPChecker: FmoHTTPChecking {
    let statusCode: Int

    func check(_ endpoint: FmoDeviceEndpoint) async throws -> Int { statusCode }
}

private nonisolated struct StubGeoChecker: FmoGeoChecking {
    func check(_ endpoint: FmoDeviceEndpoint) async throws {}
}
