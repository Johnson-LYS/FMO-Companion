import Foundation
import Testing
@testable import FMOc

@MainActor
struct FmoAudioSessionCoordinatorTests {
    @Test
    func connectedActiveSessionStartsContinuousMonitoring() async throws {
        let monitor = AudioMonitorSpy()
        let coordinator = FmoAudioSessionCoordinator(monitor: monitor)
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .bonjour)

        await coordinator.run(
            endpoint: endpoint,
            isConnected: true
        )

        #expect(monitor.monitoredEndpoint == endpoint)
        #expect(monitor.stopArguments.isEmpty)
    }

    @Test
    func disconnectedSessionStopsButPreservesTheSoundPreference() async throws {
        let monitor = AudioMonitorSpy()
        let coordinator = FmoAudioSessionCoordinator(monitor: monitor)
        let endpoint = try FmoDeviceEndpoint(host: "fmo.local", source: .bonjour)

        await coordinator.run(
            endpoint: endpoint,
            isConnected: false
        )

        #expect(monitor.stopArguments == [StopArgument(resetWaveform: true, resetSound: false)])
        #expect(monitor.monitoredEndpoint == nil)
    }

    @Test
    func cancelledObsoleteSessionCannotStopTheReplacementSession() async throws {
        let monitor = AudioMonitorSpy()
        let coordinator = FmoAudioSessionCoordinator(monitor: monitor)
        let gate = AudioSessionGate()

        let obsoleteTask = Task { @MainActor in
            await gate.wait()
            await coordinator.run(
                endpoint: nil,
                isConnected: false
            )
        }
        await gate.waitUntilOccupied()
        obsoleteTask.cancel()
        await gate.open()
        await obsoleteTask.value

        #expect(monitor.stopArguments.isEmpty)
        #expect(monitor.monitoredEndpoint == nil)
    }
}

@MainActor
private final class AudioMonitorSpy: FmoAudioMonitoring {
    private(set) var monitoredEndpoint: FmoDeviceEndpoint?
    private(set) var stopArguments: [StopArgument] = []

    func monitorContinuously(
        endpoint: FmoDeviceEndpoint,
        retryDelay: Duration
    ) async {
        monitoredEndpoint = endpoint
    }

    func stop(resetWaveform: Bool, resetSound: Bool) async {
        stopArguments.append(StopArgument(resetWaveform: resetWaveform, resetSound: resetSound))
    }
}

private struct StopArgument: Equatable {
    let resetWaveform: Bool
    let resetSound: Bool
}

private actor AudioSessionGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilOccupied() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
