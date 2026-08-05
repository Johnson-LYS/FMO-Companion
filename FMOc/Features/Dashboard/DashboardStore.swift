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

    func beginLocalStatusConnection() -> DashboardSnapshot {
        snapshot.generatedAt = dateProvider.now()
        snapshot.localStatusLink = .connecting
        return snapshot
    }

    func recordLocalStatus(_ update: DashboardLocalStatusUpdate) -> DashboardSnapshot {
        let now = dateProvider.now()
        snapshot.generatedAt = now
        snapshot.localStatusLink = .connected
        snapshot.callsign = field(update.callsign, source: .localDeviceStatus, at: now)
        snapshot.currentServerName = field(update.currentServerName, source: .localDeviceStatus, at: now)
        snapshot.filterDistance = field(update.filterDistance, source: .localDeviceStatus, at: now)
        snapshot.workingFrequencyMHz = field(update.workingFrequencyMHz, source: .localDeviceStatus, at: now)
        snapshot.qsoLogCount = field(update.qsoLogCount, source: .localDeviceStatus, at: now)
        return snapshot
    }

    func recordLocalStatusDisconnection() -> DashboardSnapshot {
        let now = dateProvider.now()
        snapshot.generatedAt = now
        snapshot.localStatusLink = .disconnected
        snapshot.callsign = stale(snapshot.callsign, at: now)
        snapshot.currentServerName = stale(snapshot.currentServerName, at: now)
        snapshot.filterDistance = stale(snapshot.filterDistance, at: now)
        snapshot.workingFrequencyMHz = stale(snapshot.workingFrequencyMHz, at: now)
        snapshot.qsoLogCount = stale(snapshot.qsoLogCount, at: now)
        return snapshot
    }

    func beginLocalEventConnection() -> DashboardSnapshot {
        snapshot.generatedAt = dateProvider.now()
        snapshot.localEventLink = .connecting
        snapshot.currentSpeaker = .unknown
        return snapshot
    }

    func recordLocalEvent(_ event: FmoLocalEvent) -> DashboardSnapshot {
        let now = dateProvider.now()
        snapshot.generatedAt = now
        snapshot.localEventLink = .connected

        switch event {
        case .speaking(let state):
            guard state.isSpeaking, let callsign = state.callsign else {
                snapshot.currentSpeaker = .unknown
                return snapshot
            }
            snapshot.currentSpeaker = .available(
                observation(
                    DashboardSpeaker(callsign: callsign, grid: state.grid),
                    source: .localEventStream,
                    observedAt: now
                )
            )

        case .history(let activities):
            guard let latest = activities.max(by: { $0.occurredAt < $1.occurredAt }) else {
                snapshot.recentLocalActivity = .unknown
                return snapshot
            }
            snapshot.recentLocalActivity = .available(
                observation(
                    DashboardLocalActivity(callsign: latest.callsign, occurredAt: latest.occurredAt),
                    source: .localEventStream,
                    observedAt: now
                )
            )
        }
        return snapshot
    }

    func recordLocalEventDisconnection() -> DashboardSnapshot {
        let now = dateProvider.now()
        snapshot.generatedAt = now
        snapshot.localEventLink = .disconnected
        snapshot.currentSpeaker = .unknown
        snapshot.recentLocalActivity = stale(snapshot.recentLocalActivity, at: now)
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

    private func field<Value>(
        _ value: Value?,
        source: DashboardFieldSource,
        at date: Date
    ) -> DashboardField<Value> where Value: Codable & Equatable & Sendable {
        guard let value else { return .unknown }
        return .available(observation(value, source: source, observedAt: date))
    }

    private func observation<Value>(
        _ value: Value,
        source: DashboardFieldSource,
        observedAt: Date
    ) -> DashboardObservation<Value> where Value: Codable & Equatable & Sendable {
        DashboardObservation(
            value: value,
            source: source,
            observedAt: observedAt,
            confidence: .trusted
        )
    }
}
