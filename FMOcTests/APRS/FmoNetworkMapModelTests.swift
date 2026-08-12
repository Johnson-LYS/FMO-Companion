import Foundation
import Testing
@testable import FMOc

@MainActor
struct FmoNetworkMapModelTests {
    @Test
    func defaultsToAutoTrackingAndCentersOnLocatedCoordinate() async throws {
        let coordinate = try GeoCoordinate(latitude: 31.2304, longitude: 121.4737)
        let model = FmoNetworkMapModel(
            locationProvider: MapLocationProvider(result: .success(coordinate))
        )

        #expect(model.isAutoTrackingEnabled)
        #expect(model.distanceScope == .km500)
        #expect(await model.locate() == coordinate)
        #expect(model.ownCoordinate == coordinate)
        #expect(model.locationErrorMessage == nil)
        #expect(!model.isLocating)
    }

    @Test
    func preparesDefault500KilometerScopeFromOwnLocation() async throws {
        let coordinate = try GeoCoordinate(latitude: 31.2304, longitude: 121.4737)
        let model = FmoNetworkMapModel(
            locationProvider: MapLocationProvider(result: .success(coordinate))
        )

        #expect(await model.prepareDefaultDistanceScope() == coordinate)
        #expect(model.distanceScope == .km500)
        #expect(model.ownCoordinate == coordinate)
    }

    @Test
    func failedDefaultScopeLocationFallsBackToAll() async {
        let model = FmoNetworkMapModel(
            locationProvider: MapLocationProvider(result: .failure(.denied))
        )

        #expect(await model.prepareDefaultDistanceScope() == nil)
        #expect(model.distanceScope == .all)
        #expect(model.locationErrorMessage == String(localized: "定位访问已关闭"))
    }

    @Test
    func exposesFriendlyLocationFailureWithoutChangingCoordinate() async {
        let model = FmoNetworkMapModel(
            locationProvider: MapLocationProvider(result: .failure(.denied))
        )

        #expect(await model.locate() == nil)
        #expect(model.ownCoordinate == nil)
        #expect(model.locationErrorMessage == String(localized: "定位访问已关闭"))

        model.dismissLocationError()
        #expect(model.locationErrorMessage == nil)
    }

    @Test
    func finiteScopeUsesOwnLocationAcrossStationsServersAndEvents() async throws {
        let center = try GeoCoordinate(latitude: 31.2304, longitude: 121.4737)
        let model = FmoNetworkMapModel(
            locationProvider: MapLocationProvider(result: .success(center))
        )
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let nearEvent = makeEvent(id: "near", latitude: 31.3, longitude: 121.5, date: date)
        let farEvent = makeEvent(id: "far", latitude: 39.9042, longitude: 116.4074, date: date)
        let snapshot = FMOV4NetworkSnapshot(events: [nearEvent, farEvent])

        #expect(await model.selectDistanceScope(.km100) == center)
        #expect(model.distanceScope == .km100)
        #expect(model.visibleSnapshot(snapshot).events.map(\.id) == ["near"])

        _ = await model.selectDistanceScope(.all)
        #expect(model.visibleSnapshot(snapshot).events.map(\.id) == ["near", "far"])
    }

    @Test
    func failedLocationDoesNotApplyFiniteScope() async {
        let model = FmoNetworkMapModel(
            locationProvider: MapLocationProvider(result: .failure(.denied))
        )

        _ = await model.selectDistanceScope(.all)

        #expect(await model.selectDistanceScope(.km500) == nil)
        #expect(model.distanceScope == .all)
    }

    private func makeEvent(
        id: String,
        latitude: Double,
        longitude: Double,
        date: Date
    ) -> FMOV4NetworkEvent {
        FMOV4NetworkEvent(
            id: id,
            kind: .cq,
            callsign: id.uppercased(),
            ssid: 10,
            latitude: latitude,
            longitude: longitude,
            serverUID: nil,
            topic: nil,
            content: nil,
            observedAt: date,
            trustLevel: .trusted
        )
    }
}

private nonisolated struct MapLocationProvider: PhoneLocationProviding {
    enum Result: Sendable {
        case success(GeoCoordinate)
        case failure(PhoneLocationError)
    }

    let result: Result

    func currentLocation() throws -> PhoneLocationSample {
        switch result {
        case .success(let coordinate):
            PhoneLocationSample(
                coordinate: coordinate,
                horizontalAccuracy: 5,
                isAccuracyLimited: false
            )
        case .failure(let error):
            throw error
        }
    }
}
