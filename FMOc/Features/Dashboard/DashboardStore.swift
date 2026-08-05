import Foundation

nonisolated protocol DashboardDateProviding: Sendable {
    func now() -> Date
}

nonisolated struct SystemDashboardDateProvider: DashboardDateProviding {
    func now() -> Date { .now }
}

actor DashboardStore {
    private let dateProvider: any DashboardDateProviding
    private var snapshot: DashboardSnapshot

    init(dateProvider: any DashboardDateProviding = SystemDashboardDateProvider()) {
        self.dateProvider = dateProvider
        snapshot = .empty()
    }

    func currentSnapshot() -> DashboardSnapshot {
        snapshot
    }

    func beginConnection() -> DashboardSnapshot {
        let now = dateProvider.now()
        snapshot = .empty(generatedAt: now)
        snapshot.geoLink = .connecting
        return snapshot
    }

    func recordGeoCoordinate(_ coordinate: GeoCoordinate) -> DashboardSnapshot {
        let now = dateProvider.now()
        snapshot.generatedAt = now
        snapshot.geoLink = .connected
        snapshot.maidenhead = .available(
            DashboardObservation(
                value: MaidenheadLocator.sixCharacterGrid(for: coordinate),
                source: .geoCoordinate,
                observedAt: now,
                confidence: .derived
            )
        )
        return snapshot
    }

    func recordGeoDisconnection() -> DashboardSnapshot {
        let now = dateProvider.now()
        snapshot.generatedAt = now
        snapshot.geoLink = .disconnected
        snapshot.maidenhead = stale(snapshot.maidenhead, at: now)
        return snapshot
    }

    func reset() -> DashboardSnapshot {
        snapshot = .empty(generatedAt: dateProvider.now())
        return snapshot
    }

    private func stale<Value>(
        _ field: DashboardField<Value>,
        at date: Date
    ) -> DashboardField<Value> where Value: Codable & Equatable & Sendable {
        switch field {
        case let .available(observation):
            .stale(observation, staleAt: date)
        case let .stale(observation, staleAt):
            .stale(observation, staleAt: staleAt)
        case .unknown, .unsupported, .rejected:
            field
        }
    }
}
