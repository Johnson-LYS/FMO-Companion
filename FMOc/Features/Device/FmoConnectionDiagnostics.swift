import Foundation

nonisolated enum FmoDiagnosticStep: Int, CaseIterable, Identifiable, Sendable {
    case localNetwork
    case endpoint
    case http
    case geo

    var id: Int { rawValue }
}

nonisolated enum FmoDiagnosticEvidence: Equatable, Sendable {
    case wifiAvailable
    case endpointReachable(port: Int)
    case httpResponse(statusCode: Int)
    case geoResponse
}

nonisolated enum FmoDiagnosticFailure: Error, Equatable, Sendable {
    case wifiUnavailable
    case localNetworkDenied
    case resolutionFailed
    case endpointUnavailable
    case httpUnavailable
    case geo(FmoDeviceError)
    case timedOut
}

nonisolated enum FmoDiagnosticState: Equatable, Sendable {
    case pending
    case running
    case passed(FmoDiagnosticEvidence)
    case failed(FmoDiagnosticFailure)
    case skipped
}

nonisolated struct FmoDiagnosticUpdate: Equatable, Sendable {
    let step: FmoDiagnosticStep
    let state: FmoDiagnosticState
}

nonisolated protocol FmoLocalNetworkChecking: Sendable {
    func check() async throws
}

nonisolated protocol FmoEndpointChecking: Sendable {
    func check(_ endpoint: FmoDeviceEndpoint) async throws -> Int
}

nonisolated protocol FmoHTTPChecking: Sendable {
    func check(_ endpoint: FmoDeviceEndpoint) async throws -> Int
}

nonisolated protocol FmoGeoChecking: Sendable {
    func check(_ endpoint: FmoDeviceEndpoint) async throws
}

nonisolated protocol FmoConnectionDiagnosing: Sendable {
    func diagnose(_ endpoint: FmoDeviceEndpoint) -> AsyncStream<FmoDiagnosticUpdate>
}

actor FmoConnectionDiagnoser: FmoConnectionDiagnosing {
    private let localNetwork: any FmoLocalNetworkChecking
    private let endpoint: any FmoEndpointChecking
    private let http: any FmoHTTPChecking
    private let geo: any FmoGeoChecking

    init(
        localNetwork: any FmoLocalNetworkChecking = NWLocalNetworkChecker(),
        endpoint: any FmoEndpointChecking = NWEndpointChecker(),
        http: any FmoHTTPChecking = URLSessionFmoHTTPChecker(),
        geo: any FmoGeoChecking = FmoGeoChecker()
    ) {
        self.localNetwork = localNetwork
        self.endpoint = endpoint
        self.http = http
        self.geo = geo
    }

    nonisolated func diagnose(_ endpoint: FmoDeviceEndpoint) -> AsyncStream<FmoDiagnosticUpdate> {
        AsyncStream { continuation in
            let task = Task {
                await self.run(endpoint, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func run(
        _ deviceEndpoint: FmoDeviceEndpoint,
        continuation: AsyncStream<FmoDiagnosticUpdate>.Continuation
    ) async {
        for step in FmoDiagnosticStep.allCases {
            guard !Task.isCancelled else {
                continuation.finish()
                return
            }

            continuation.yield(FmoDiagnosticUpdate(step: step, state: .running))

            do {
                let evidence = try await evidence(for: step, endpoint: deviceEndpoint)
                continuation.yield(FmoDiagnosticUpdate(step: step, state: .passed(evidence)))
            } catch is CancellationError {
                continuation.finish()
                return
            } catch {
                let failure = failure(for: step, error: error)
                continuation.yield(FmoDiagnosticUpdate(step: step, state: .failed(failure)))
                for skipped in FmoDiagnosticStep.allCases where skipped.rawValue > step.rawValue {
                    continuation.yield(FmoDiagnosticUpdate(step: skipped, state: .skipped))
                }
                continuation.finish()
                return
            }
        }

        continuation.finish()
    }

    private func evidence(
        for step: FmoDiagnosticStep,
        endpoint deviceEndpoint: FmoDeviceEndpoint
    ) async throws -> FmoDiagnosticEvidence {
        switch step {
        case .localNetwork:
            try await localNetwork.check()
            return .wifiAvailable
        case .endpoint:
            return .endpointReachable(port: try await endpoint.check(deviceEndpoint))
        case .http:
            return .httpResponse(statusCode: try await http.check(deviceEndpoint))
        case .geo:
            try await geo.check(deviceEndpoint)
            return .geoResponse
        }
    }

    private func failure(for step: FmoDiagnosticStep, error: any Error) -> FmoDiagnosticFailure {
        if let failure = error as? FmoDiagnosticFailure { return failure }
        if let deviceError = error as? FmoDeviceError { return .geo(deviceError) }
        if let urlError = error as? URLError, urlError.code == .timedOut { return .timedOut }

        return switch step {
        case .localNetwork: .wifiUnavailable
        case .endpoint: .endpointUnavailable
        case .http: .httpUnavailable
        case .geo: .geo(.disconnected)
        }
    }
}
