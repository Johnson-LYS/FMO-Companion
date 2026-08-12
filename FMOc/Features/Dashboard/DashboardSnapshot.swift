import Foundation

nonisolated enum DashboardFieldSource: String, Codable, Equatable, Sendable {
    case geoCoordinate
    case localDeviceStatus
    case localEventStream
    case aprs
}

nonisolated enum DashboardConfidence: String, Codable, Equatable, Sendable {
    case trusted
    case derived
    case unverified
}

nonisolated struct DashboardObservation<Value>: Codable, Equatable, Sendable
where Value: Codable & Equatable & Sendable {
    let value: Value
    let source: DashboardFieldSource
    let observedAt: Date
    let confidence: DashboardConfidence
}

nonisolated enum DashboardField<Value>: Codable, Equatable, Sendable
where Value: Codable & Equatable & Sendable {
    case available(DashboardObservation<Value>)
    case unknown
    case stale(DashboardObservation<Value>, staleAt: Date)
    case unsupported
    case rejected(reason: String)

    var value: Value? {
        switch self {
        case let .available(observation), let .stale(observation, _):
            observation.value
        case .unknown, .unsupported, .rejected:
            nil
        }
    }

    var currentValue: Value? {
        guard case .available(let observation) = self else { return nil }
        return observation.value
    }
}

nonisolated enum DashboardLinkState: String, Codable, Equatable, Sendable {
    case disconnected
    case connecting
    case connected
}

nonisolated enum DashboardFilterDistance: Codable, Equatable, Sendable {
    case disabled
    case kilometers(Int)
}

nonisolated struct DashboardSpeaker: Codable, Equatable, Sendable {
    let callsign: String
    let grid: String?
    let coordinate: GeoCoordinate?

    init(callsign: String, grid: String?, coordinate: GeoCoordinate? = nil) {
        self.callsign = callsign
        self.grid = grid
        self.coordinate = coordinate
    }
}

nonisolated struct DashboardLocalActivity: Codable, Equatable, Sendable {
    let callsign: String
    let occurredAt: Date
    let grid: String?
    let coordinate: GeoCoordinate?

    init(
        callsign: String,
        occurredAt: Date,
        grid: String? = nil,
        coordinate: GeoCoordinate? = nil
    ) {
        self.callsign = callsign
        self.occurredAt = occurredAt
        self.grid = grid
        self.coordinate = coordinate
    }
}

nonisolated struct DashboardLocalStatusUpdate: Equatable, Sendable {
    var callsign: String? = nil
    var currentServerName: String? = nil
    var filterDistance: DashboardFilterDistance? = nil
    var workingFrequencyMHz: Double? = nil
    var qsoLogCount: Int? = nil

    var availableFieldCount: Int {
        [
            callsign != nil,
            currentServerName != nil,
            filterDistance != nil,
            workingFrequencyMHz != nil,
            qsoLogCount != nil
        ].count(where: { $0 })
    }
}

nonisolated struct DashboardSnapshot: Codable, Equatable, Sendable {
    var generatedAt: Date
    var geoLink: DashboardLinkState
    var localStatusLink: DashboardLinkState
    var localEventLink: DashboardLinkState
    var callsign: DashboardField<String>
    var currentServerName: DashboardField<String>
    var filterDistance: DashboardField<DashboardFilterDistance>
    var maidenhead: DashboardField<String>
    var qsoLogCount: DashboardField<Int>
    var workingFrequencyMHz: DashboardField<Double>
    var currentSpeaker: DashboardField<DashboardSpeaker>
    var recentLocalActivity: DashboardField<DashboardLocalActivity>
    var recentLocalActivities: [DashboardLocalActivity]

    static func empty(generatedAt: Date = .distantPast) -> DashboardSnapshot {
        DashboardSnapshot(
            generatedAt: generatedAt,
            geoLink: .disconnected,
            localStatusLink: .disconnected,
            localEventLink: .disconnected,
            callsign: .unknown,
            currentServerName: .unknown,
            filterDistance: .unknown,
            maidenhead: .unknown,
            qsoLogCount: .unknown,
            workingFrequencyMHz: .unknown,
            currentSpeaker: .unknown,
            recentLocalActivity: .unknown,
            recentLocalActivities: []
        )
    }
}
