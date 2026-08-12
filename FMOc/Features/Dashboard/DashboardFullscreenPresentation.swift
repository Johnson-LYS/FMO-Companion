import Foundation

nonisolated enum DashboardTargetLocationSource: Equatable, Sendable {
    case aprs(observedAt: Date)
    case cached
    case maidenhead(grid: String)
}

nonisolated struct DashboardFullscreenTarget: Equatable, Sendable {
    let callsign: String
    let isSpeaking: Bool
    let coordinate: GeoCoordinate?
    let grid: String?
    let source: DashboardTargetLocationSource?
    let distanceKilometers: Double?
    let bearingDegrees: Double?

    var cardinalDirection: String? {
        guard let bearingDegrees else { return nil }
        let directions = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        let index = Int((bearingDegrees + 22.5) / 45).quotientAndRemainder(dividingBy: 8).remainder
        return directions[index]
    }
}

nonisolated struct DashboardFullscreenHistoryItem: Equatable, Sendable {
    let callsign: String
    let occurredAt: Date
    let coordinate: GeoCoordinate?

    var id: String {
        "\(callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())-\(occurredAt.timeIntervalSince1970)"
    }
}

nonisolated struct DashboardFullscreenPresentation: Equatable, Sendable {
    let target: DashboardFullscreenTarget?
    let recentSpeakers: [DashboardFullscreenHistoryItem]

    static func make(
        dashboard: DashboardSnapshot,
        ownCoordinate: GeoCoordinate?,
        network: FMOV4NetworkSnapshot,
        now: Date = .now,
        aprsFreshness: TimeInterval = 30 * 60
    ) -> DashboardFullscreenPresentation {
        let retainedActivity = dashboard.recentLocalActivities.first
            ?? dashboard.recentLocalActivity.value
        let speaker = dashboard.currentSpeaker.value
            ?? retainedActivity.map {
                DashboardSpeaker(
                    callsign: $0.callsign,
                    grid: $0.grid,
                    coordinate: $0.coordinate
                )
            }
        let isSpeaking = dashboard.currentSpeaker.currentValue != nil
        let target = speaker.map {
            makeTarget(
                speaker: $0,
                isSpeaking: isSpeaking,
                dashboard: dashboard,
                ownCoordinate: ownCoordinate,
                network: network,
                now: now,
                aprsFreshness: aprsFreshness
            )
        }
        let currentCallsign = speaker.map { normalizedAddress($0.callsign) }
        var historyActivities = dashboard.recentLocalActivities
            .sorted { $0.occurredAt > $1.occurredAt }
        if let currentCallsign,
           let currentOccurrence = historyActivities.firstIndex(where: {
               normalizedAddress($0.callsign) == currentCallsign
           }) {
            historyActivities.remove(at: currentOccurrence)
        }
        let history = Array(historyActivities.map { activity in
            let historyTarget = makeTarget(
                speaker: DashboardSpeaker(
                    callsign: activity.callsign,
                    grid: activity.grid,
                    coordinate: activity.coordinate
                ),
                isSpeaking: false,
                dashboard: dashboard,
                ownCoordinate: nil,
                network: network,
                now: now,
                aprsFreshness: aprsFreshness
            )
            return DashboardFullscreenHistoryItem(
                callsign: activity.callsign,
                occurredAt: activity.occurredAt,
                coordinate: historyTarget.coordinate
            )
        }.prefix(10))
        return DashboardFullscreenPresentation(target: target, recentSpeakers: history)
    }

    private static func makeTarget(
        speaker: DashboardSpeaker,
        isSpeaking: Bool,
        dashboard: DashboardSnapshot,
        ownCoordinate: GeoCoordinate?,
        network: FMOV4NetworkSnapshot,
        now: Date,
        aprsFreshness: TimeInterval
    ) -> DashboardFullscreenTarget {
        let normalizedSpeaker = normalizedAddress(speaker.callsign)
        let baseCallsign = baseCallsign(normalizedSpeaker)
        var candidates = network.stations.filter {
            $0.callsign.uppercased() == baseCallsign
                && now.timeIntervalSince($0.observedAt) >= 0
                && now.timeIntervalSince($0.observedAt) <= aprsFreshness
        }

        if normalizedSpeaker.contains("-"),
           let exact = candidates.first(where: { $0.id.uppercased() == normalizedSpeaker }),
           candidates.count(where: { $0.id.uppercased() == normalizedSpeaker }) == 1 {
            candidates = [exact]
        } else {
            if let grid = normalizedGrid(speaker.grid) {
                candidates = candidates.filter {
                    guard let coordinate = try? GeoCoordinate(
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    ) else { return false }
                    return MaidenheadLocator.sixCharacterGrid(for: coordinate).uppercased() == grid
                }
            }

            if let serverUID = currentServerUID(dashboard: dashboard, network: network) {
                candidates = candidates.filter { $0.serverUID == serverUID }
            }
        }

        let location: (GeoCoordinate, DashboardTargetLocationSource)?
        if candidates.count == 1,
           let station = candidates.first,
           let coordinate = try? GeoCoordinate(latitude: station.latitude, longitude: station.longitude) {
            location = (coordinate, .aprs(observedAt: station.observedAt))
        } else if let coordinate = speaker.coordinate {
            if let grid = speaker.grid,
               MaidenheadGrid.center(of: grid) == coordinate {
                location = (coordinate, .maidenhead(grid: grid.uppercased()))
            } else {
                location = (coordinate, .cached)
            }
        } else if let grid = speaker.grid,
                  let coordinate = MaidenheadGrid.center(of: grid) {
            location = (coordinate, .maidenhead(grid: grid.uppercased()))
        } else {
            location = nil
        }

        let distanceAndBearing = ownCoordinate.flatMap { own in
            location.map { metrics(from: own, to: $0.0) }
        }
        return DashboardFullscreenTarget(
            callsign: speaker.callsign,
            isSpeaking: isSpeaking,
            coordinate: location?.0,
            grid: speaker.grid?.uppercased(),
            source: location?.1,
            distanceKilometers: distanceAndBearing?.distanceKilometers,
            bearingDegrees: distanceAndBearing?.bearingDegrees
        )
    }

    private static func currentServerUID(
        dashboard: DashboardSnapshot,
        network: FMOV4NetworkSnapshot
    ) -> UInt64? {
        guard let name = dashboard.currentServerName.currentValue else { return nil }
        let matches = network.servers.filter {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard matches.count == 1 else { return nil }
        return matches[0].uid
    }

    private static func normalizedGrid(_ grid: String?) -> String? {
        guard let grid else { return nil }
        let normalized = grid.uppercased()
        guard normalized.count == 6, MaidenheadGrid.isValid(normalized) else { return nil }
        return normalized
    }

    private static func normalizedAddress(_ callsign: String) -> String {
        callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func baseCallsign(_ callsign: String) -> String {
        callsign.split(separator: "-", maxSplits: 1).first.map(String.init) ?? callsign
    }

    private static func metrics(
        from origin: GeoCoordinate,
        to target: GeoCoordinate
    ) -> (distanceKilometers: Double, bearingDegrees: Double) {
        let latitude1 = origin.latitude * .pi / 180
        let latitude2 = target.latitude * .pi / 180
        let latitudeDelta = (target.latitude - origin.latitude) * .pi / 180
        let longitudeDelta = (target.longitude - origin.longitude) * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitude1) * cos(latitude2)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let distance = 6_371.0088 * 2 * atan2(sqrt(a), sqrt(1 - a))
        let y = sin(longitudeDelta) * cos(latitude2)
        let x = cos(latitude1) * sin(latitude2)
            - sin(latitude1) * cos(latitude2) * cos(longitudeDelta)
        let bearing = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return (distance, bearing)
    }
}
