import Foundation
import Testing
@testable import FMOc

struct LocationSyncPolicyTests {
    private let evaluator = LocationSyncEvaluator()
    private let origin = try! GeoCoordinate(latitude: 0, longitude: 0)

    @Test
    func modesExposeConfirmedPresetsAndAuthorizationRequirements() {
        #expect(LocationSyncMode.manual.throttlePolicy == nil)
        #expect(LocationSyncMode.manual.requiresAlwaysAuthorization == false)
        #expect(LocationSyncMode.lowPower.throttlePolicy == .lowPower)
        #expect(LocationSyncMode.lowPower.requiresAlwaysAuthorization)
        #expect(LocationSyncMode.vehicle.throttlePolicy == .vehicle)
        #expect(LocationSyncMode.vehicle.requiresAlwaysAuthorization)
        #expect(LocationSyncPolicy.lowPower.minimumElapsedTime == 900)
        #expect(LocationSyncPolicy.lowPower.minimumDistanceMeters == 1_000)
        #expect(LocationSyncPolicy.vehicle.minimumElapsedTime == 120)
        #expect(LocationSyncPolicy.vehicle.minimumDistanceMeters == 250)
    }

    @Test
    func manualModeNeverAutomaticallySynchronizes() {
        let candidate = sample(at: 10_000)

        #expect(
            evaluator.evaluate(
                mode: .manual,
                candidate: candidate,
                lastSuccessfulSync: nil
            ) == .manualOnly
        )
    }

    @Test(arguments: [LocationSyncMode.lowPower, .vehicle])
    func firstAutomaticSampleSynchronizesImmediately(mode: LocationSyncMode) {
        let candidate = sample(at: 10_000)

        #expect(
            evaluator.evaluate(
                mode: mode,
                candidate: candidate,
                lastSuccessfulSync: nil
            ) == .synchronize(.initial)
        )
    }

    @Test
    func lowPowerModeSynchronizesAtExactTimeBoundary() {
        let lastSuccess = sample(at: 1_000)
        let candidate = sample(at: 1_900)

        #expect(
            evaluator.evaluate(
                mode: .lowPower,
                candidate: candidate,
                lastSuccessfulSync: lastSuccess
            ) == .synchronize(.elapsedTime)
        )
    }

    @Test
    func lowPowerModeThrottlesWhenBothThresholdsAreBelowMinimum() throws {
        let lastSuccess = sample(at: 1_000)
        let nearbyCoordinate = try GeoCoordinate(latitude: 0, longitude: 0.008)
        let candidate = sample(coordinate: nearbyCoordinate, at: 1_899)

        #expect(
            evaluator.evaluate(
                mode: .lowPower,
                candidate: candidate,
                lastSuccessfulSync: lastSuccess
            ) == .throttled
        )
    }

    @Test
    func lowPowerModeUsesOrSemanticsForDistance() throws {
        let lastSuccess = sample(at: 1_000)
        let distantCoordinate = try GeoCoordinate(latitude: 0, longitude: 0.01)
        let candidate = sample(coordinate: distantCoordinate, at: 1_001)

        #expect(
            evaluator.evaluate(
                mode: .lowPower,
                candidate: candidate,
                lastSuccessfulSync: lastSuccess
            ) == .synchronize(.distance)
        )
    }

    @Test
    func decisionReportsWhenBothThresholdsAreReached() throws {
        let lastSuccess = sample(at: 1_000)
        let distantCoordinate = try GeoCoordinate(latitude: 0, longitude: 0.01)
        let candidate = sample(coordinate: distantCoordinate, at: 1_900)

        #expect(
            evaluator.evaluate(
                mode: .lowPower,
                candidate: candidate,
                lastSuccessfulSync: lastSuccess
            ) == .synchronize(.elapsedTimeAndDistance)
        )
    }

    @Test
    func vehicleModeUsesVehiclePreset() throws {
        let lastSuccess = sample(at: 1_000)
        let movedCoordinate = try GeoCoordinate(latitude: 0, longitude: 0.003)

        #expect(
            evaluator.evaluate(
                mode: .vehicle,
                candidate: sample(at: 1_120),
                lastSuccessfulSync: lastSuccess
            ) == .synchronize(.elapsedTime)
        )
        #expect(
            evaluator.evaluate(
                mode: .vehicle,
                candidate: sample(coordinate: movedCoordinate, at: 1_001),
                lastSuccessfulSync: lastSuccess
            ) == .synchronize(.distance)
        )
    }

    private func sample(
        coordinate: GeoCoordinate? = nil,
        at timestamp: TimeInterval
    ) -> LocationSyncSample {
        LocationSyncSample(
            coordinate: coordinate ?? origin,
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }
}
