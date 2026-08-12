import Foundation
import Observation

nonisolated enum FmoNetworkDistanceScope: Int, CaseIterable, Identifiable, Sendable {
    case all = 0
    case km50 = 50
    case km100 = 100
    case km200 = 200
    case km500 = 500
    case km1000 = 1_000
    case km2000 = 2_000
    case km5000 = 5_000

    var id: Self { self }
    var kilometers: Double? { self == .all ? nil : Double(rawValue) }
}

@MainActor
@Observable
final class FmoNetworkMapModel {
    private let locationProvider: any PhoneLocationProviding

    var isAutoTrackingEnabled = true
    var distanceScope = FmoNetworkDistanceScope.km500
    var ownCoordinate: GeoCoordinate?
    var isLocating = false
    var locationErrorMessage: String?

    init(locationProvider: any PhoneLocationProviding = CoreLocationProvider()) {
        self.locationProvider = locationProvider
    }

    func prepareDefaultDistanceScope() async -> GeoCoordinate? {
        guard distanceScope != .all else { return ownCoordinate }
        if let ownCoordinate { return ownCoordinate }

        guard let coordinate = await locate() else {
            distanceScope = .all
            return nil
        }
        return coordinate
    }

    func selectDistanceScope(_ scope: FmoNetworkDistanceScope) async -> GeoCoordinate? {
        if scope == .all {
            distanceScope = scope
            return ownCoordinate
        }

        let center: GeoCoordinate
        if let ownCoordinate {
            center = ownCoordinate
        } else {
            guard let located = await locate() else { return nil }
            center = located
        }
        distanceScope = scope
        return center
    }

    func visibleSnapshot(_ snapshot: FMOV4NetworkSnapshot) -> FMOV4NetworkSnapshot {
        guard let maximumKilometers = distanceScope.kilometers,
              let center = ownCoordinate
        else {
            return snapshot
        }

        return FMOV4NetworkSnapshot(
            stations: snapshot.stations.filter {
                Self.distanceKilometers(
                    from: center,
                    latitude: $0.latitude,
                    longitude: $0.longitude
                ) <= maximumKilometers
            },
            servers: snapshot.servers.filter {
                Self.distanceKilometers(
                    from: center,
                    latitude: $0.latitude,
                    longitude: $0.longitude
                ) <= maximumKilometers
            },
            events: snapshot.events.filter {
                Self.distanceKilometers(
                    from: center,
                    latitude: $0.latitude,
                    longitude: $0.longitude
                ) <= maximumKilometers
            },
            rejectedCounts: snapshot.rejectedCounts
        )
    }

    func locate() async -> GeoCoordinate? {
        guard !isLocating else { return nil }
        isLocating = true
        locationErrorMessage = nil
        defer { isLocating = false }

        do {
            let sample = try await locationProvider.currentLocation()
            ownCoordinate = sample.coordinate
            return sample.coordinate
        } catch {
            locationErrorMessage = (error as? any LocalizedError)?.errorDescription
                ?? String(localized: "暂时无法获取当前位置")
            return nil
        }
    }

    func dismissLocationError() {
        locationErrorMessage = nil
    }

    private static func distanceKilometers(
        from center: GeoCoordinate,
        latitude: Double,
        longitude: Double
    ) -> Double {
        let earthRadiusKilometers = 6_371.0088
        let latitudeDelta = (latitude - center.latitude) * .pi / 180
        let longitudeDelta = (longitude - center.longitude) * .pi / 180
        let centerLatitude = center.latitude * .pi / 180
        let targetLatitude = latitude * .pi / 180
        let haversine = pow(sin(latitudeDelta / 2), 2)
            + cos(centerLatitude) * cos(targetLatitude) * pow(sin(longitudeDelta / 2), 2)
        return earthRadiusKilometers * 2 * atan2(sqrt(haversine), sqrt(1 - haversine))
    }
}
