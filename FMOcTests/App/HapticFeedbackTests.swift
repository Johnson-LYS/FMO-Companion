import Foundation
import Testing
@testable import FMOc

struct HapticFeedbackTests {
    @Test
    func reportsSpeakerStartAndEndEdges() {
        let idle = state(callsign: nil)
        let speaking = state(callsign: "BI8SYN")

        #expect(DashboardSpeakerHapticPolicy.event(from: idle, to: speaking) == .started)
        #expect(DashboardSpeakerHapticPolicy.event(from: speaking, to: idle) == .ended)
    }

    @Test
    func speakerChangeIsOnlyAStartEvent() {
        let first = state(callsign: "BI8SYN")
        let next = state(callsign: "BG1ABC")

        #expect(DashboardSpeakerHapticPolicy.event(from: first, to: next) == .started)
    }

    @Test
    func repeatedSpeakerStateDoesNotProduceFeedback() {
        let speaking = state(callsign: "bi8syn")
        let normalizedRepeat = state(callsign: " BI8SYN ")

        #expect(DashboardSpeakerHapticPolicy.event(from: speaking, to: normalizedRepeat) == nil)
    }

    @Test
    func disconnectDoesNotMasqueradeAsSpeakerEnd() {
        let speaking = state(callsign: "BI8SYN")
        let disconnected = state(callsign: nil, eventLink: .disconnected)

        #expect(DashboardSpeakerHapticPolicy.event(from: speaking, to: disconnected) == nil)
    }

    @Test
    func visibilityAndPreferenceGateFeedback() {
        let hidden = state(callsign: nil, isEligible: false)
        let visibleSpeaking = state(callsign: "BI8SYN")
        let visibleIdle = state(callsign: nil)
        let hiddenSpeaking = state(callsign: "BI8SYN", isEligible: false)

        #expect(DashboardSpeakerHapticPolicy.event(from: hidden, to: visibleSpeaking) == nil)
        #expect(DashboardSpeakerHapticPolicy.event(from: visibleIdle, to: hiddenSpeaking) == nil)
    }

    private func state(
        callsign: String?,
        eventLink: DashboardLinkState = .connected,
        isEligible: Bool = true
    ) -> DashboardSpeakerHapticState {
        var snapshot = DashboardSnapshot.empty()
        snapshot.localEventLink = eventLink
        if let callsign {
            snapshot.currentSpeaker = .available(
                DashboardObservation(
                    value: DashboardSpeaker(callsign: callsign, grid: nil),
                    source: .localEventStream,
                    observedAt: .now,
                    confidence: .trusted
                )
            )
        }
        return DashboardSpeakerHapticState(snapshot: snapshot, isEligible: isEligible)
    }
}
