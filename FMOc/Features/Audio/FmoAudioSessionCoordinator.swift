import Foundation

@MainActor
protocol FmoAudioMonitoring: AnyObject {
    func monitorContinuously(
        endpoint: FmoDeviceEndpoint,
        retryDelay: Duration
    ) async
    func stop(resetWaveform: Bool, resetSound: Bool) async
}

extension FmoAudioMonitorModel: FmoAudioMonitoring {}

@MainActor
struct FmoAudioSessionCoordinator {
    let monitor: any FmoAudioMonitoring

    func run(
        endpoint: FmoDeviceEndpoint?,
        isConnected: Bool
    ) async {
        guard !Task.isCancelled else { return }

        guard isConnected, let endpoint else {
            await monitor.stop(resetWaveform: true, resetSound: false)
            return
        }

        await monitor.monitorContinuously(
            endpoint: endpoint,
            retryDelay: .seconds(1)
        )
    }
}
