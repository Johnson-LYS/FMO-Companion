import UIKit

@MainActor
protocol IdleTimerStatusWriting: AnyObject {
    var isIdleTimerDisabled: Bool { get set }
}

extension UIApplication: IdleTimerStatusWriting {}

nonisolated struct DashboardIdleTimerState: Equatable, Sendable {
    let isFullscreenPresented: Bool
    let isSceneActive: Bool
}

@MainActor
protocol DashboardIdleTimerControlling: AnyObject {
    func update(_ state: DashboardIdleTimerState)
    func restore()
}

@MainActor
final class DashboardIdleTimerController: DashboardIdleTimerControlling {
    private let application: any IdleTimerStatusWriting
    private var isManagingIdleTimer = false
    private var previousValue = false

    init(application: any IdleTimerStatusWriting = UIApplication.shared) {
        self.application = application
    }

    func update(_ state: DashboardIdleTimerState) {
        let shouldDisable = state.isFullscreenPresented && state.isSceneActive

        if shouldDisable, !isManagingIdleTimer {
            previousValue = application.isIdleTimerDisabled
            application.isIdleTimerDisabled = true
            isManagingIdleTimer = true
        } else if !shouldDisable {
            restore()
        }
    }

    func restore() {
        guard isManagingIdleTimer else { return }
        application.isIdleTimerDisabled = previousValue
        isManagingIdleTimer = false
    }
}
