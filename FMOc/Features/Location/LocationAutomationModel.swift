import Foundation
import Observation

@MainActor
@Observable
final class LocationAutomationModel {
    private let coordinator: any AutomaticLocationSyncCoordinating
    private let authorizationReader: any LocationAuthorizationReading
    private var snapshotTask: Task<Void, Never>?
    private var hasRestored = false

    var snapshot = AutomaticLocationSyncSnapshot()
    var authorization = LocationAuthorizationState.notDetermined

    init(
        coordinator: any AutomaticLocationSyncCoordinating,
        authorizationReader: any LocationAuthorizationReading
    ) {
        self.coordinator = coordinator
        self.authorizationReader = authorizationReader
        authorization = authorizationReader.currentStatus()
    }

    func restoreIfNeeded() async {
        guard !hasRestored else {
            refreshAuthorization()
            return
        }
        hasRestored = true
        observeSnapshots()
        await coordinator.restore()
        snapshot = await coordinator.currentSnapshot()
        refreshAuthorization()
    }

    func select(_ mode: LocationSyncMode) async {
        refreshAuthorization()
        if mode == .manual {
            await coordinator.stop()
        } else {
            await coordinator.start(mode: mode)
        }
        snapshot = await coordinator.currentSnapshot()
        refreshAuthorization()
    }

    func stop() async {
        await select(.manual)
    }

    func resume() async {
        await coordinator.resume()
        snapshot = await coordinator.currentSnapshot()
        refreshAuthorization()
    }

    func refreshAuthorization() {
        authorization = authorizationReader.currentStatus()
    }

    private func observeSnapshots() {
        snapshotTask?.cancel()
        let coordinator = self.coordinator
        snapshotTask = Task { [weak self] in
            let snapshots = await coordinator.snapshots()
            for await snapshot in snapshots {
                guard let self else { return }
                self.snapshot = snapshot
                self.refreshAuthorization()
            }
        }
    }
}
