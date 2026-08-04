import Foundation
import Testing
@testable import FMOc

struct LocationSyncModeStoreTests {
    @Test
    func defaultsToManualWhenNothingWasSaved() async throws {
        let fixture = try Fixture()
        defer { fixture.removePersistentDomain() }

        let store = UserDefaultsLocationSyncModeStore(
            defaults: fixture.defaults,
            key: fixture.key
        )

        #expect(await store.load() == .manual)
    }

    @Test(arguments: [LocationSyncMode.manual, .lowPower, .vehicle])
    func roundTripsMode(mode: LocationSyncMode) async throws {
        let fixture = try Fixture()
        defer { fixture.removePersistentDomain() }
        let store = UserDefaultsLocationSyncModeStore(
            defaults: fixture.defaults,
            key: fixture.key
        )

        await store.save(mode)

        #expect(await store.load() == mode)
    }

    @Test
    func invalidPersistedValueFallsBackToManual() async throws {
        let fixture = try Fixture()
        defer { fixture.removePersistentDomain() }
        fixture.defaults.set("unsupported", forKey: fixture.key)
        let store = UserDefaultsLocationSyncModeStore(
            defaults: fixture.defaults,
            key: fixture.key
        )

        #expect(await store.load() == .manual)
    }

    private final class Fixture: @unchecked Sendable {
        let suiteName: String
        let defaults: UserDefaults
        let key = "mode"

        init() throws {
            suiteName = "LocationSyncModeStoreTests.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suiteName))
        }

        func removePersistentDomain() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
