import Foundation

nonisolated protocol DateProviding: Sendable {
    func now() -> Date
}

nonisolated struct SystemDateProvider: DateProviding {
    func now() -> Date { .now }
}

nonisolated protocol RetryWaiting: Sendable {
    func wait(for delay: Duration) async throws
}

nonisolated struct TaskRetryWaiter: RetryWaiting {
    func wait(for delay: Duration) async throws {
        try await Task.sleep(for: delay)
    }
}

nonisolated struct LocationSyncBackoffPolicy: Equatable, Sendable {
    static let `default` = LocationSyncBackoffPolicy(delays: [
        .seconds(1),
        .seconds(2),
        .seconds(4),
        .seconds(8),
        .seconds(16),
        .seconds(30),
        .seconds(60),
    ])

    let delays: [Duration]

    func delay(forRetry retry: Int) -> Duration {
        guard !delays.isEmpty else { return .zero }
        return delays[min(max(0, retry), delays.count - 1)]
    }
}

nonisolated enum AutomaticLocationSyncCause: Equatable, Sendable {
    case location(LocationSyncTrigger)
    case networkRecovery
    case retry
}

nonisolated enum AutomaticLocationSyncPauseReason: Equatable, Sendable {
    case networkUnavailable
    case noDevice
    case location(AutomaticLocationPauseReason)
    case locationStreamFailed
}

nonisolated enum AutomaticLocationSyncPhase: Equatable, Sendable {
    case stopped
    case starting
    case waitingForLocation
    case syncing(AutomaticLocationSyncCause)
    case retrying(attempt: Int, delay: Duration)
    case paused(AutomaticLocationSyncPauseReason)
}

nonisolated enum LocationSyncAttemptResult: Equatable, Sendable {
    case inProgress
    case success
    case failure(FmoDeviceError)
}

nonisolated struct LocationSyncAttempt: Equatable, Sendable {
    let timestamp: Date
    let result: LocationSyncAttemptResult
}

nonisolated struct AutomaticLocationSyncSnapshot: Equatable, Sendable {
    var mode: LocationSyncMode = .manual
    var phase: AutomaticLocationSyncPhase = .stopped
    var lastAttempt: LocationSyncAttempt?
    var lastSuccessAt: Date?
}

nonisolated protocol AutomaticLocationSyncCoordinating: Sendable {
    func restore() async
    func start(mode: LocationSyncMode) async
    func stop() async
    func resume() async
    func currentSnapshot() async -> AutomaticLocationSyncSnapshot
    func snapshots() async -> AsyncStream<AutomaticLocationSyncSnapshot>
}
