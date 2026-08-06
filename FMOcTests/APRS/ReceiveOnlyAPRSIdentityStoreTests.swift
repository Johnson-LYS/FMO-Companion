import Foundation
import Testing
@testable import FMOc

struct ReceiveOnlyAPRSIdentityStoreTests {
    @Test
    func manualIdentityPersistsAcrossStoreInstances() async throws {
        let suiteName = makeSuiteName()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "BG0TST", ssid: 10)

        await UserDefaultsReceiveOnlyAPRSIdentityStore(suiteName: suiteName)
            .saveManual(identity)
        let restored = await UserDefaultsReceiveOnlyAPRSIdentityStore(suiteName: suiteName)
            .load()

        #expect(
            restored == ReceiveOnlyAPRSIdentityConfiguration(
                identity: identity,
                source: .manual
            )
        )
    }

    @Test
    func inheritedIdentityCannotOverwriteManualIdentity() async throws {
        let suiteName = makeSuiteName()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let manual = try ReceiveOnlyAPRSIdentity(callsign: "BG0OWN", ssid: 12)
        let inherited = try ReceiveOnlyAPRSIdentity(callsign: "BG0BOX", ssid: 10)
        let sut = UserDefaultsReceiveOnlyAPRSIdentityStore(suiteName: suiteName)

        await sut.saveManual(manual)
        await sut.adoptInherited(inherited)

        let restored = await sut.load()
        #expect(
            restored == ReceiveOnlyAPRSIdentityConfiguration(
                identity: manual,
                source: .manual
            )
        )
    }

    @Test
    func invalidPersistedIdentityIsIgnored() async throws {
        let suiteName = makeSuiteName()
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        defaults.set("INVALID-CALL", forKey: "aprs.receiveOnlyIdentity.callsign")
        defaults.set(10, forKey: "aprs.receiveOnlyIdentity.ssid")
        defaults.set("manual", forKey: "aprs.receiveOnlyIdentity.source")
        let sut = UserDefaultsReceiveOnlyAPRSIdentityStore(suiteName: suiteName)

        let restored = await sut.load()
        #expect(restored == nil)
    }

    private func makeSuiteName() -> String {
        "ReceiveOnlyAPRSIdentityStoreTests.\(UUID().uuidString)"
    }
}
