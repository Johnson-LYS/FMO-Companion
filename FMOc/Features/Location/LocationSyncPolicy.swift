import Foundation

nonisolated enum LocationSyncMode: String, CaseIterable, Codable, Sendable {
    case manual
    case lowPower
    case vehicle

    var requiresAlwaysAuthorization: Bool {
        self != .manual
    }

    var throttlePolicy: LocationSyncPolicy? {
        switch self {
        case .manual:
            nil
        case .lowPower:
            .lowPower
        case .vehicle:
            .vehicle
        }
    }
}

nonisolated struct LocationSyncSample: Equatable, Sendable {
    let coordinate: GeoCoordinate
    let timestamp: Date
}

nonisolated enum LocationSyncTrigger: Equatable, Sendable {
    case initial
    case elapsedTime
    case distance
    case elapsedTimeAndDistance
}

nonisolated enum LocationSyncDecision: Equatable, Sendable {
    case manualOnly
    case synchronize(LocationSyncTrigger)
    case throttled
}

nonisolated struct LocationSyncPolicy: Equatable, Sendable {
    static let lowPower = LocationSyncPolicy(
        minimumElapsedTime: 15 * 60,
        minimumDistanceMeters: 1_000
    )

    static let vehicle = LocationSyncPolicy(
        minimumElapsedTime: 2 * 60,
        minimumDistanceMeters: 250
    )

    let minimumElapsedTime: TimeInterval
    let minimumDistanceMeters: Double

    func evaluate(
        candidate: LocationSyncSample,
        lastSuccessfulSync: LocationSyncSample?
    ) -> LocationSyncDecision {
        guard let lastSuccessfulSync else {
            return .synchronize(.initial)
        }

        let elapsedTimeReached = candidate.timestamp.timeIntervalSince(lastSuccessfulSync.timestamp)
            >= minimumElapsedTime
        let distanceReached = candidate.coordinate.distance(to: lastSuccessfulSync.coordinate)
            >= minimumDistanceMeters

        switch (elapsedTimeReached, distanceReached) {
        case (true, true):
            return .synchronize(.elapsedTimeAndDistance)
        case (true, false):
            return .synchronize(.elapsedTime)
        case (false, true):
            return .synchronize(.distance)
        case (false, false):
            return .throttled
        }
    }
}

nonisolated struct LocationSyncEvaluator: Sendable {
    func evaluate(
        mode: LocationSyncMode,
        candidate: LocationSyncSample,
        lastSuccessfulSync: LocationSyncSample?
    ) -> LocationSyncDecision {
        guard let policy = mode.throttlePolicy else {
            return .manualOnly
        }

        return policy.evaluate(
            candidate: candidate,
            lastSuccessfulSync: lastSuccessfulSync
        )
    }
}

private extension GeoCoordinate {
    nonisolated func distance(to other: GeoCoordinate) -> Double {
        let earthRadiusMeters = 6_371_008.8
        let latitudeDelta = (other.latitude - latitude).radians
        let longitudeDelta = (other.longitude - longitude).radians
        let originLatitude = latitude.radians
        let destinationLatitude = other.latitude.radians

        let haversine = pow(sin(latitudeDelta / 2), 2)
            + cos(originLatitude) * cos(destinationLatitude)
            * pow(sin(longitudeDelta / 2), 2)
        let normalizedHaversine = min(1, max(0, haversine))

        return earthRadiusMeters * 2
            * atan2(sqrt(normalizedHaversine), sqrt(1 - normalizedHaversine))
    }
}

private extension Double {
    nonisolated var radians: Double {
        self * .pi / 180
    }
}
