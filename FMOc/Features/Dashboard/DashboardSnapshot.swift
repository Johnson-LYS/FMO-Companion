import Foundation

nonisolated enum DashboardFieldSource: String, Codable, Equatable, Sendable {
    case geoCoordinate
    case deviceStatus
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
}

nonisolated enum DashboardLinkState: String, Codable, Equatable, Sendable {
    case disconnected
    case connecting
    case connected
}

nonisolated struct DashboardRadioFrequencies: Codable, Equatable, Sendable {
    let transmitMHz: Double
    let receiveMHz: Double
}

nonisolated struct DashboardServerOccupancy: Codable, Equatable, Sendable {
    let online: Int
    let maximum: Int
}

nonisolated struct DashboardEvent: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case voiceActivity
        case cq
        case online
        case station
    }

    let kind: Kind
    let callsign: String?
    let summary: String?
    let observedAt: Date
}

nonisolated struct DashboardSnapshot: Codable, Equatable, Sendable {
    var generatedAt: Date
    var geoLink: DashboardLinkState
    var callsign: DashboardField<String>
    var currentServerName: DashboardField<String>
    var filterDistanceKilometers: DashboardField<Int>
    var maidenhead: DashboardField<String>
    var liveQSOCount: DashboardField<Int>
    var radioFrequencies: DashboardField<DashboardRadioFrequencies>
    var serverLatencyMilliseconds: DashboardField<Int>
    var serverAdministratorCallsign: DashboardField<String>
    var serverOccupancy: DashboardField<DashboardServerOccupancy>
    var latestEvent: DashboardField<DashboardEvent>

    static func empty(generatedAt: Date = .distantPast) -> DashboardSnapshot {
        DashboardSnapshot(
            generatedAt: generatedAt,
            geoLink: .disconnected,
            callsign: .unsupported,
            currentServerName: .unsupported,
            filterDistanceKilometers: .unsupported,
            maidenhead: .unknown,
            liveQSOCount: .unsupported,
            radioFrequencies: .unsupported,
            serverLatencyMilliseconds: .unsupported,
            serverAdministratorCallsign: .unsupported,
            serverOccupancy: .unsupported,
            latestEvent: .unsupported
        )
    }
}
