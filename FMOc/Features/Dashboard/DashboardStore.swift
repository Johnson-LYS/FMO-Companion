import Foundation

nonisolated protocol DashboardDateProviding: Sendable {
    func now() -> Date
}

nonisolated struct SystemDashboardDateProvider: DashboardDateProviding {
    func now() -> Date { .now }
}

actor DashboardStore {
    private let dateProvider: any DashboardDateProviding
    private let speakerLocationStore: any DashboardSpeakerLocationStoring
    private var snapshot: DashboardSnapshot

    init(
        dateProvider: any DashboardDateProviding = SystemDashboardDateProvider(),
        speakerLocationStore: any DashboardSpeakerLocationStoring = VolatileDashboardSpeakerLocationStore()
    ) {
        self.dateProvider = dateProvider
        self.speakerLocationStore = speakerLocationStore
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

    func recordCurrentServer(_ serverName: String) -> DashboardSnapshot {
        let now = dateProvider.now()
        snapshot.generatedAt = now
        snapshot.localStatusLink = .connected
        snapshot.currentServerName = .available(
            observation(serverName, source: .localDeviceStatus, observedAt: now)
        )
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
        let now = dateProvider.now()
        snapshot.generatedAt = now
        snapshot.localEventLink = .connecting
        snapshot.currentSpeaker = stale(snapshot.currentSpeaker, at: now)
        return snapshot
    }

    func recordLocalEvent(_ event: FmoLocalEvent) async -> DashboardSnapshot {
        let now = dateProvider.now()
        snapshot.generatedAt = now
        snapshot.localEventLink = .connected

        switch event {
        case .speaking(let state):
            guard state.isSpeaking, let callsign = state.callsign else {
                snapshot.currentSpeaker = stale(snapshot.currentSpeaker, at: now)
                return snapshot
            }
            if let previous = snapshot.currentSpeaker.value,
               previous.callsign.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(callsign.trimmingCharacters(in: .whitespacesAndNewlines))
                != .orderedSame,
               !snapshot.recentLocalActivities.contains(where: {
                   $0.callsign.caseInsensitiveCompare(previous.callsign) == .orderedSame
               }) {
                snapshot.recentLocalActivities.insert(
                    DashboardLocalActivity(
                        callsign: previous.callsign,
                        occurredAt: now,
                        grid: previous.grid,
                        coordinate: previous.coordinate
                    ),
                    at: 0
                )
                snapshot.recentLocalActivities = Array(snapshot.recentLocalActivities.prefix(20))
            }
            let cachedLocation = await speakerLocationStore.location(for: callsign)
            let eventGrid = state.grid?.trimmingCharacters(in: .whitespacesAndNewlines)
            let gridCoordinate = eventGrid.flatMap(MaidenheadGrid.center(of:))
            let coordinate = gridCoordinate ?? cachedLocation?.coordinate
            let effectiveGrid = eventGrid ?? cachedLocation?.grid
            if let coordinate {
                await speakerLocationStore.save(
                    DashboardSpeakerLocation(
                        callsign: callsign,
                        coordinate: coordinate,
                        grid: effectiveGrid,
                        areaName: cachedLocation?.areaName,
                        updatedAt: now
                    )
                )
            }
            snapshot.currentSpeaker = .available(
                observation(
                    DashboardSpeaker(
                        callsign: callsign,
                        grid: effectiveGrid,
                        coordinate: coordinate
                    ),
                    source: .localEventStream,
                    observedAt: now
                )
            )

        case .history(let activities):
            let retainedLocations = Dictionary(
                snapshot.recentLocalActivities.compactMap { activity in
                    let key = activity.callsign
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .uppercased()
                    return (key, activity)
                },
                uniquingKeysWith: { first, _ in first }
            )
            var recent: [DashboardLocalActivity] = []
            for activity in activities {
                let key = activity.callsign
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                let retained = retainedLocations[key]
                let cached = await speakerLocationStore.location(for: key)
                recent.append(
                    DashboardLocalActivity(
                        callsign: activity.callsign,
                        occurredAt: activity.occurredAt,
                        grid: retained?.grid ?? cached?.grid,
                        coordinate: retained?.coordinate ?? cached?.coordinate
                    )
                )
            }
            recent.sort { $0.occurredAt > $1.occurredAt }
            snapshot.recentLocalActivities = Array(recent.prefix(20))
            guard let latest = recent.first else {
                snapshot.recentLocalActivity = .unknown
                return snapshot
            }
            snapshot.recentLocalActivity = .available(
                observation(
                    latest,
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
        snapshot.currentSpeaker = stale(snapshot.currentSpeaker, at: now)
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
