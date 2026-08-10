import Foundation
import Testing
@testable import FMOc

struct FmoRemoteControlCounterStoreTests {
    @Test
    func incrementsWithinMinuteAndResetsAcrossMinutesAndRestarts() async {
        let suite = "FmoRemoteControlCounterStoreTests.\(UUID())"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let target = TNC2Address(callsign: "BG5ESN", ssid: 10)
        let firstStore = UserDefaultsFmoRemoteControlCounterStore(suiteName: suite)

        #expect(await firstStore.next(for: target, timeSlot: 100).counter == 0)
        #expect(await firstStore.next(for: target, timeSlot: 100).counter == 1)

        let restoredStore = UserDefaultsFmoRemoteControlCounterStore(suiteName: suite)
        #expect(await restoredStore.next(for: target, timeSlot: 100).counter == 2)
        #expect(await restoredStore.next(for: target, timeSlot: 101).counter == 0)
    }
}
