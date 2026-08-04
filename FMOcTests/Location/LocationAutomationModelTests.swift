import Foundation
import Testing
@testable import FMOc

@MainActor
struct LocationAutomationModelTests {
    @Test
    func restoresCoordinatorOnlyOnceAndRefreshesAuthorization() async {
        let coordinator = RecordingLocationAutomationCoordinator()
        let authorization = StubAuthorizationReader(status: .whenInUse)
        let model = LocationAutomationModel(
            coordinator: coordinator,
            authorizationReader: authorization
        )

        await model.restoreIfNeeded()
        authorization.status = .always
        await model.restoreIfNeeded()

        #expect(await coordinator.restoreCallCount() == 1)
        #expect(model.authorization == .always)
    }

    @Test
    func selectingAutomaticModeAndStoppingUpdateVisibleSnapshot() async {
        let coordinator = RecordingLocationAutomationCoordinator()
        let model = LocationAutomationModel(
            coordinator: coordinator,
            authorizationReader: StubAuthorizationReader(status: .always)
        )

        await model.select(.vehicle)
        #expect(model.snapshot.mode == .vehicle)
        #expect(model.snapshot.phase == .waitingForLocation)
        #expect(await coordinator.startedModes() == [.vehicle])

        await model.stop()
        #expect(model.snapshot.mode == .manual)
        #expect(model.snapshot.phase == .stopped)
        #expect(await coordinator.stopCallCount() == 1)
    }

    @Test
    func observesCoordinatorSnapshots() async {
        let coordinator = RecordingLocationAutomationCoordinator()
        let model = LocationAutomationModel(
            coordinator: coordinator,
            authorizationReader: StubAuthorizationReader(status: .always)
        )
        await model.restoreIfNeeded()

        await coordinator.publish(
            AutomaticLocationSyncSnapshot(
                mode: .lowPower,
                phase: .paused(.networkUnavailable)
            )
        )

        #expect(await eventually { model.snapshot.phase == .paused(.networkUnavailable) })
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
}

@MainActor
private final class StubAuthorizationReader: LocationAuthorizationReading {
    var status: LocationAuthorizationState

    init(status: LocationAuthorizationState) {
        self.status = status
    }

    func currentStatus() -> LocationAuthorizationState { status }
}

private actor RecordingLocationAutomationCoordinator: AutomaticLocationSyncCoordinating {
    private var snapshot = AutomaticLocationSyncSnapshot()
    private var restoreCalls = 0
    private var stopCalls = 0
    private var modes: [LocationSyncMode] = []
    private var observers: [AsyncStream<AutomaticLocationSyncSnapshot>.Continuation] = []

    func restore() {
        restoreCalls += 1
    }

    func start(mode: LocationSyncMode) {
        modes.append(mode)
        snapshot.mode = mode
        snapshot.phase = .waitingForLocation
        yieldSnapshot()
    }

    func stop() {
        stopCalls += 1
        snapshot.mode = .manual
        snapshot.phase = .stopped
        yieldSnapshot()
    }

    func resume() {}

    func currentSnapshot() -> AutomaticLocationSyncSnapshot { snapshot }

    func snapshots() -> AsyncStream<AutomaticLocationSyncSnapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            observers.append(continuation)
            continuation.yield(snapshot)
        }
    }

    func publish(_ snapshot: AutomaticLocationSyncSnapshot) {
        self.snapshot = snapshot
        yieldSnapshot()
    }

    func restoreCallCount() -> Int { restoreCalls }
    func stopCallCount() -> Int { stopCalls }
    func startedModes() -> [LocationSyncMode] { modes }

    private func yieldSnapshot() {
        for observer in observers {
            observer.yield(snapshot)
        }
    }
}
