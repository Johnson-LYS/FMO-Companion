import Observation

@MainActor
@Observable
final class DeviceDiagnosticsModel {
    private let diagnoser: any FmoConnectionDiagnosing

    private(set) var states: [FmoDiagnosticStep: FmoDiagnosticState]
    private(set) var isRunning = false

    init(diagnoser: any FmoConnectionDiagnosing) {
        self.diagnoser = diagnoser
        self.states = Dictionary(
            uniqueKeysWithValues: FmoDiagnosticStep.allCases.map { ($0, .pending) }
        )
    }

    func state(for step: FmoDiagnosticStep) -> FmoDiagnosticState {
        states[step] ?? .pending
    }

    func run(endpoint: FmoDeviceEndpoint) async {
        states = Dictionary(
            uniqueKeysWithValues: FmoDiagnosticStep.allCases.map { ($0, .pending) }
        )
        isRunning = true
        defer { isRunning = false }

        for await update in diagnoser.diagnose(endpoint) {
            guard !Task.isCancelled else { return }
            states[update.step] = update.state
        }
    }
}
