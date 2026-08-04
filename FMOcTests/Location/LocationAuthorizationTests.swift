import CoreLocation
import Testing
@testable import FMOc

struct LocationAuthorizationTests {
    @Test(arguments: [
        (CLAuthorizationStatus.notDetermined, LocationAuthorizationState.notDetermined),
        (.authorizedWhenInUse, .whenInUse),
        (.authorizedAlways, .always),
        (.denied, .denied),
        (.restricted, .restricted),
    ])
    func mapsSystemAuthorization(
        status: CLAuthorizationStatus,
        expected: LocationAuthorizationState
    ) {
        #expect(LocationAuthorizationState(status) == expected)
    }

    @Test
    func manualModeAcceptsWhenInUseOrAlways() {
        #expect(LocationAuthorizationState.whenInUse.isSufficient(for: .manual))
        #expect(LocationAuthorizationState.always.isSufficient(for: .manual))
        #expect(!LocationAuthorizationState.denied.isSufficient(for: .manual))
    }

    @Test(arguments: [LocationSyncMode.lowPower, .vehicle])
    func automaticModesRequireAlways(mode: LocationSyncMode) {
        #expect(LocationAuthorizationState.always.isSufficient(for: mode))
        #expect(!LocationAuthorizationState.whenInUse.isSufficient(for: mode))
        #expect(!LocationAuthorizationState.notDetermined.isSufficient(for: mode))
    }
}
