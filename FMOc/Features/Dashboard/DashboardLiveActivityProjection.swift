import Foundation

nonisolated struct DashboardLiveActivityPreferences: Codable, Equatable, Sendable {
    var showsCallsign: Bool
    var showsLocation: Bool

    static let `default` = DashboardLiveActivityPreferences(
        showsCallsign: true,
        showsLocation: false
    )
}

nonisolated struct DashboardLiveActivityPayload: Equatable, Sendable {
    let state: FmoDashboardActivityAttributes.ContentState
    let staleDate: Date

    var hasUsefulContent: Bool {
        state.callsign != nil || state.serverName != nil || state.activity != nil
    }
}

nonisolated enum DashboardLiveActivityProjection {
    static let defaultStalenessInterval: TimeInterval = 15 * 60

    static func makePayload(
        from snapshot: DashboardSnapshot,
        preferences: DashboardLiveActivityPreferences,
        now: Date,
        stalenessInterval: TimeInterval = defaultStalenessInterval
    ) -> DashboardLiveActivityPayload {
        let callsign = preferences.showsCallsign
            ? clipped(snapshot.callsign.value, maximumCharacters: 16)
            : nil
        let serverName = clipped(snapshot.currentServerName.value, maximumCharacters: 64)
        let maidenhead = preferences.showsLocation
            ? clipped(snapshot.maidenhead.value, maximumCharacters: 8)
            : nil
        let activity = activity(from: snapshot, showsLocation: preferences.showsLocation)
        let connection = connectionState(for: snapshot, hasCachedContent: [callsign, serverName, maidenhead].contains { $0 != nil } || activity != nil)
        let updatedAt = snapshot.generatedAt == .distantPast ? now : snapshot.generatedAt
        let proposedStaleDate = updatedAt.addingTimeInterval(stalenessInterval)
        let staleDate = connection == .connected ? max(now, proposedStaleDate) : now

        return DashboardLiveActivityPayload(
            state: FmoDashboardActivityAttributes.ContentState(
                connection: connection,
                callsign: callsign,
                serverName: serverName,
                maidenhead: maidenhead,
                activity: activity,
                updatedAt: updatedAt
            ),
            staleDate: staleDate
        )
    }

    private static func connectionState(
        for snapshot: DashboardSnapshot,
        hasCachedContent: Bool
    ) -> FmoDashboardActivityAttributes.ContentState.Connection {
        if snapshot.geoLink == .connected {
            return .connected
        }
        return hasCachedContent ? .stale : .disconnected
    }

    private static func activity(
        from snapshot: DashboardSnapshot,
        showsLocation: Bool
    ) -> FmoDashboardActivityAttributes.ContentState.ActivityItem? {
        if let speaker = snapshot.currentSpeaker.currentValue,
           let callsign = clipped(speaker.callsign, maximumCharacters: 16) {
            return FmoDashboardActivityAttributes.ContentState.ActivityItem(
                kind: .speaking,
                callsign: callsign,
                grid: showsLocation ? clipped(speaker.grid, maximumCharacters: 8) : nil,
                occurredAt: nil
            )
        }

        if let recent = snapshot.recentLocalActivity.value,
           let callsign = clipped(recent.callsign, maximumCharacters: 16) {
            return FmoDashboardActivityAttributes.ContentState.ActivityItem(
                kind: .recent,
                callsign: callsign,
                grid: nil,
                occurredAt: recent.occurredAt
            )
        }

        return nil
    }

    private static func clipped(_ value: String?, maximumCharacters: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumCharacters))
    }
}
