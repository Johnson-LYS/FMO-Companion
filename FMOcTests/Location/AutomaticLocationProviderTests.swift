import Testing
@testable import FMOc

struct AutomaticLocationProviderTests {
    @Test
    func rejectsManualModeWithoutStartingCoreLocationSessions() async {
        let provider = CoreLocationAutomaticProvider()

        await #expect(throws: AutomaticLocationError.manualMode) {
            _ = try await provider.updates(for: .manual)
        }
    }

    @Test
    func stoppingWithoutAnActiveStreamIsSafe() async {
        let provider = CoreLocationAutomaticProvider()

        await provider.stop()
        await provider.stop()
    }
}
