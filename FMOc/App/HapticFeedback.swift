import SwiftUI

nonisolated enum HapticPreferences {
    static let speakerEventsEnabledKey = "haptics.speakerEvents.enabled"
}

nonisolated enum AppHapticKind: Equatable, Sendable {
    case selection
    case lightImpact
    case mediumImpact
    case success
    case warning
    case error
}

nonisolated struct AppHapticPulse: Equatable, Sendable {
    let id: UUID
    let kind: AppHapticKind

    init(_ kind: AppHapticKind, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
    }
}

nonisolated enum DashboardSpeakerHapticEvent: Equatable, Sendable {
    case started
    case ended
}

nonisolated struct DashboardSpeakerHapticState: Equatable, Sendable {
    let callsign: String?
    let eventLink: DashboardLinkState
    let isEligible: Bool

    init(snapshot: DashboardSnapshot, isEligible: Bool) {
        callsign = snapshot.currentSpeaker.currentValue?.callsign
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        eventLink = snapshot.localEventLink
        self.isEligible = isEligible
    }
}

nonisolated enum DashboardSpeakerHapticPolicy {
    static func event(
        from oldState: DashboardSpeakerHapticState,
        to newState: DashboardSpeakerHapticState
    ) -> DashboardSpeakerHapticEvent? {
        guard oldState.isEligible, newState.isEligible,
              newState.eventLink == .connected else {
            return nil
        }

        switch (oldState.callsign, newState.callsign) {
        case (nil, .some):
            return .started
        case let (.some(oldCallsign), .some(newCallsign)) where oldCallsign != newCallsign:
            return .started
        case (.some, nil):
            return .ended
        default:
            return nil
        }
    }
}

extension View {
    func appSensoryFeedback(trigger: AppHapticPulse?) -> some View {
        sensoryFeedback(trigger: trigger) { oldValue, newValue in
            guard oldValue?.id != newValue?.id, let kind = newValue?.kind else { return nil }
            return kind.sensoryFeedback
        }
    }
}

private extension AppHapticKind {
    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .selection: .selection
        case .lightImpact: .impact(weight: .light)
        case .mediumImpact: .impact(weight: .medium)
        case .success: .success
        case .warning: .warning
        case .error: .error
        }
    }
}
