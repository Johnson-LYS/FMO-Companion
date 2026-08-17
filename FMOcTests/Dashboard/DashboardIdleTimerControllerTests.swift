import Testing
@testable import FMOc

@MainActor
struct DashboardIdleTimerControllerTests {
    @Test
    func disablesIdleTimerOnlyForActiveFullscreenPresentation() {
        let application = IdleTimerApplicationStub()
        let controller = DashboardIdleTimerController(application: application)

        controller.update(.init(isFullscreenPresented: false, isSceneActive: true))
        #expect(!application.isIdleTimerDisabled)

        controller.update(.init(isFullscreenPresented: true, isSceneActive: true))
        #expect(application.isIdleTimerDisabled)

        controller.update(.init(isFullscreenPresented: true, isSceneActive: false))
        #expect(!application.isIdleTimerDisabled)
    }

    @Test
    func restoresTheValueThatExistedBeforeFullscreenPresentation() {
        let application = IdleTimerApplicationStub(isIdleTimerDisabled: true)
        let controller = DashboardIdleTimerController(application: application)

        controller.update(.init(isFullscreenPresented: true, isSceneActive: true))
        controller.restore()

        #expect(application.isIdleTimerDisabled)
    }
}

@MainActor
private final class IdleTimerApplicationStub: IdleTimerStatusWriting {
    var isIdleTimerDisabled: Bool

    init(isIdleTimerDisabled: Bool = false) {
        self.isIdleTimerDisabled = isIdleTimerDisabled
    }
}
