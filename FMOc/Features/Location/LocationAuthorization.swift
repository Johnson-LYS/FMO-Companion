import CoreLocation

nonisolated enum LocationAuthorizationState: String, Codable, Equatable, Sendable {
    case notDetermined
    case whenInUse
    case always
    case denied
    case restricted

    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .authorizedWhenInUse:
            self = .whenInUse
        case .authorizedAlways:
            self = .always
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .denied
        }
    }

    func isSufficient(for mode: LocationSyncMode) -> Bool {
        switch mode {
        case .manual:
            self == .whenInUse || self == .always
        case .lowPower, .vehicle:
            self == .always
        }
    }
}

@MainActor
protocol LocationAuthorizationReading: Sendable {
    func currentStatus() -> LocationAuthorizationState
}

@MainActor
final class CoreLocationAuthorizationReader: LocationAuthorizationReading {
    private let locationManager: CLLocationManager

    init(locationManager: CLLocationManager = CLLocationManager()) {
        self.locationManager = locationManager
    }

    func currentStatus() -> LocationAuthorizationState {
        LocationAuthorizationState(locationManager.authorizationStatus)
    }
}
