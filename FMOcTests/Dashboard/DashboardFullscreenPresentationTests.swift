import Foundation
import Testing
@testable import FMOc

struct DashboardFullscreenPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func usesUniqueRecentAPRSStationAndCalculatesDistanceAndBearing() throws {
        var dashboard = DashboardSnapshot.empty()
        dashboard.currentSpeaker = available(
            DashboardSpeaker(callsign: "BH4XYZ", grid: nil),
            at: now
        )
        dashboard.currentServerName = available("测试服务器", at: now)
        let station = makeStation(
            id: "BH4XYZ-15",
            callsign: "BH4XYZ",
            latitude: 0,
            longitude: 1,
            serverUID: 42
        )
        let server = makeServer(uid: 42, name: "测试服务器")

        let presentation = DashboardFullscreenPresentation.make(
            dashboard: dashboard,
            ownCoordinate: try GeoCoordinate(latitude: 0, longitude: 0),
            network: FMOV4NetworkSnapshot(stations: [station], servers: [server]),
            now: now
        )

        let target = try #require(presentation.target)
        #expect(target.coordinate == (try GeoCoordinate(latitude: 0, longitude: 1)))
        guard case .aprs(let observedAt) = target.source else {
            Issue.record("唯一近期 APRS 台站应作为精细位置")
            return
        }
        #expect(observedAt == now.addingTimeInterval(-60))
        #expect(abs((target.distanceKilometers ?? 0) - 111.2) < 0.2)
        #expect(abs((target.bearingDegrees ?? 0) - 90) < 0.01)
        #expect(target.cardinalDirection == String(localized: "东"))
        #expect(target.isSpeaking)
    }

    @Test
    func fallsBackToMaidenheadCenterWhenAPRSIdentityIsAmbiguous() throws {
        var dashboard = DashboardSnapshot.empty()
        dashboard.currentSpeaker = available(
            DashboardSpeaker(callsign: "BH4XYZ", grid: "PM01RF"),
            at: now
        )
        let first = makeStation(
            id: "BH4XYZ-10",
            callsign: "BH4XYZ",
            latitude: 32,
            longitude: 122,
            serverUID: nil
        )
        let second = makeStation(
            id: "BH4XYZ-15",
            callsign: "BH4XYZ",
            latitude: 33,
            longitude: 123,
            serverUID: nil
        )

        let presentation = DashboardFullscreenPresentation.make(
            dashboard: dashboard,
            ownCoordinate: try GeoCoordinate(latitude: 31.2304, longitude: 121.4737),
            network: FMOV4NetworkSnapshot(stations: [first, second]),
            now: now
        )

        let target = try #require(presentation.target)
        #expect(target.coordinate == MaidenheadGrid.center(of: "PM01RF"))
        #expect(target.source == .maidenhead(grid: "PM01RF"))
    }

    @Test
    func doesNotGuessBetweenMultipleSSIDCandidatesWithoutGrid() throws {
        var dashboard = DashboardSnapshot.empty()
        dashboard.currentSpeaker = available(
            DashboardSpeaker(callsign: "BH4XYZ", grid: nil),
            at: now
        )

        let presentation = DashboardFullscreenPresentation.make(
            dashboard: dashboard,
            ownCoordinate: try GeoCoordinate(latitude: 31, longitude: 121),
            network: FMOV4NetworkSnapshot(stations: [
                makeStation(id: "BH4XYZ-10", callsign: "BH4XYZ", latitude: 31, longitude: 122),
                makeStation(id: "BH4XYZ-15", callsign: "BH4XYZ", latitude: 32, longitude: 122),
            ]),
            now: now
        )

        #expect(presentation.target?.coordinate == nil)
        #expect(presentation.target?.distanceKilometers == nil)
    }

    @Test
    func rejectsExpiredAPRSPositionAndUsesEventGrid() throws {
        var dashboard = DashboardSnapshot.empty()
        dashboard.currentSpeaker = available(
            DashboardSpeaker(callsign: "BH4XYZ", grid: "PM01RF"),
            at: now
        )
        var staleStation = makeStation(
            id: "BH4XYZ-15",
            callsign: "BH4XYZ",
            latitude: 0,
            longitude: 1
        )
        staleStation = FMOV4StationRecord(
            id: staleStation.id,
            callsign: staleStation.callsign,
            ssid: staleStation.ssid,
            latitude: staleStation.latitude,
            longitude: staleStation.longitude,
            serverUID: staleStation.serverUID,
            frequency: staleStation.frequency,
            lastActivity: staleStation.lastActivity,
            observedAt: now.addingTimeInterval(-31 * 60),
            certificateExpiresAt: staleStation.certificateExpiresAt,
            issuerSerialNumber: staleStation.issuerSerialNumber,
            trustLevel: staleStation.trustLevel,
            rootCRL: staleStation.rootCRL,
            intermediateCRL: staleStation.intermediateCRL
        )

        let presentation = DashboardFullscreenPresentation.make(
            dashboard: dashboard,
            ownCoordinate: try GeoCoordinate(latitude: 31, longitude: 121),
            network: FMOV4NetworkSnapshot(stations: [staleStation]),
            now: now
        )

        #expect(presentation.target?.source == .maidenhead(grid: "PM01RF"))
    }

    @Test
    func keepsRepeatedSpeakingTurnsAndExcludesOnlyCurrentOccurrence() {
        var dashboard = DashboardSnapshot.empty()
        dashboard.currentSpeaker = available(
            DashboardSpeaker(callsign: "BH4XYZ", grid: nil),
            at: now
        )
        dashboard.recentLocalActivities = [
            DashboardLocalActivity(callsign: "BH4XYZ", occurredAt: now),
            DashboardLocalActivity(callsign: "BG0AAA", occurredAt: now.addingTimeInterval(-10)),
            DashboardLocalActivity(callsign: "bg0aaa", occurredAt: now.addingTimeInterval(-20)),
            DashboardLocalActivity(callsign: "BD7ABC", occurredAt: now.addingTimeInterval(-30)),
        ]

        let presentation = DashboardFullscreenPresentation.make(
            dashboard: dashboard,
            ownCoordinate: nil,
            network: .empty,
            now: now
        )

        #expect(presentation.recentSpeakers.map(\.callsign) == ["BG0AAA", "bg0aaa", "BD7ABC"])
    }

    @Test
    func keepsAlternatingCallsignsAsIndependentHistoryRows() {
        var dashboard = DashboardSnapshot.empty()
        dashboard.currentSpeaker = available(
            DashboardSpeaker(callsign: "BG1AAA", grid: nil),
            at: now
        )
        dashboard.recentLocalActivities = [
            DashboardLocalActivity(callsign: "BG1AAA", occurredAt: now),
            DashboardLocalActivity(callsign: "BG2BBB", occurredAt: now.addingTimeInterval(-10)),
            DashboardLocalActivity(callsign: "BG1AAA", occurredAt: now.addingTimeInterval(-20)),
            DashboardLocalActivity(callsign: "BG2BBB", occurredAt: now.addingTimeInterval(-30)),
        ]

        let presentation = DashboardFullscreenPresentation.make(
            dashboard: dashboard,
            ownCoordinate: nil,
            network: .empty,
            now: now
        )

        #expect(presentation.recentSpeakers.map(\.callsign) == ["BG2BBB", "BG1AAA", "BG2BBB"])
        #expect(Set(presentation.recentSpeakers.map(\.id)).count == 3)
    }

    @Test
    func keepsOnlyTenNewestHistorySpeakersInDescendingOrder() {
        var dashboard = DashboardSnapshot.empty()
        dashboard.currentSpeaker = available(
            DashboardSpeaker(callsign: "BH4XYZ", grid: nil),
            at: now
        )
        dashboard.recentLocalActivities = (0..<12).map { index in
            DashboardLocalActivity(
                callsign: "BG\(index)AAA",
                occurredAt: now.addingTimeInterval(Double(index))
            )
        }

        let presentation = DashboardFullscreenPresentation.make(
            dashboard: dashboard,
            ownCoordinate: nil,
            network: .empty,
            now: now
        )

        #expect(presentation.recentSpeakers.count == 10)
        #expect(presentation.recentSpeakers.map(\.callsign) == [
            "BG11AAA", "BG10AAA", "BG9AAA", "BG8AAA", "BG7AAA",
            "BG6AAA", "BG5AAA", "BG4AAA", "BG3AAA", "BG2AAA",
        ])
    }

    @Test
    func attachesUniqueRecentAPRSCoordinateToHistorySpeaker() throws {
        var dashboard = DashboardSnapshot.empty()
        dashboard.currentSpeaker = available(
            DashboardSpeaker(callsign: "BH4XYZ", grid: nil),
            at: now
        )
        dashboard.recentLocalActivities = [
            DashboardLocalActivity(callsign: "BG0AAA", occurredAt: now.addingTimeInterval(-10))
        ]
        let station = makeStation(
            id: "BG0AAA-15",
            callsign: "BG0AAA",
            latitude: 36.0611,
            longitude: 103.8343
        )

        let presentation = DashboardFullscreenPresentation.make(
            dashboard: dashboard,
            ownCoordinate: nil,
            network: FMOV4NetworkSnapshot(stations: [station]),
            now: now
        )

        let history = try #require(presentation.recentSpeakers.first)
        #expect(history.callsign == "BG0AAA")
        #expect(history.coordinate == (try GeoCoordinate(latitude: 36.0611, longitude: 103.8343)))
    }

    @Test
    func usesPersistedCoordinateWhenHistoryHasNoCurrentNetworkCandidate() throws {
        let coordinate = try GeoCoordinate(latitude: 39.9042, longitude: 116.4074)
        var dashboard = DashboardSnapshot.empty()
        dashboard.recentLocalActivities = [
            DashboardLocalActivity(
                callsign: "BG1AAA",
                occurredAt: now,
                grid: "OM89AA",
                coordinate: coordinate
            ),
            DashboardLocalActivity(
                callsign: "BG2BBB",
                occurredAt: now.addingTimeInterval(-10),
                grid: nil,
                coordinate: coordinate
            ),
        ]

        let presentation = DashboardFullscreenPresentation.make(
            dashboard: dashboard,
            ownCoordinate: nil,
            network: .empty,
            now: now
        )

        #expect(presentation.target?.coordinate == coordinate)
        #expect(presentation.target?.source == .cached)
        #expect(presentation.recentSpeakers.first?.coordinate == coordinate)
    }

    @Test
    func retainsFinishedSpeakerInMainPositionUntilNextSpeakerStarts() {
        var dashboard = DashboardSnapshot.empty()
        dashboard.currentSpeaker = .stale(
            DashboardObservation(
                value: DashboardSpeaker(callsign: "BH4XYZ", grid: "PM01RF"),
                source: .localEventStream,
                observedAt: now.addingTimeInterval(-10),
                confidence: .trusted
            ),
            staleAt: now
        )
        dashboard.recentLocalActivities = [
            DashboardLocalActivity(callsign: "BH4XYZ", occurredAt: now.addingTimeInterval(-10)),
            DashboardLocalActivity(callsign: "BG0AAA", occurredAt: now.addingTimeInterval(-20)),
        ]

        let presentation = DashboardFullscreenPresentation.make(
            dashboard: dashboard,
            ownCoordinate: nil,
            network: .empty,
            now: now
        )

        #expect(presentation.target?.callsign == "BH4XYZ")
        #expect(presentation.target?.isSpeaking == false)
        #expect(presentation.recentSpeakers.map(\.callsign) == ["BG0AAA"])
    }

    @Test
    func promotesLatestHistoryToInactiveMainPositionWhenOpeningDuringIdle() {
        var dashboard = DashboardSnapshot.empty()
        dashboard.recentLocalActivities = [
            DashboardLocalActivity(callsign: "BG0AAA", occurredAt: now.addingTimeInterval(-10)),
            DashboardLocalActivity(callsign: "BD7ABC", occurredAt: now.addingTimeInterval(-20)),
        ]

        let presentation = DashboardFullscreenPresentation.make(
            dashboard: dashboard,
            ownCoordinate: nil,
            network: .empty,
            now: now
        )

        #expect(presentation.target?.callsign == "BG0AAA")
        #expect(presentation.target?.isSpeaking == false)
        #expect(presentation.recentSpeakers.map(\.callsign) == ["BD7ABC"])
    }

    private func makeStation(
        id: String,
        callsign: String,
        latitude: Double,
        longitude: Double,
        serverUID: UInt64? = nil
    ) -> FMOV4StationRecord {
        FMOV4StationRecord(
            id: id,
            callsign: callsign,
            ssid: UInt8(id.split(separator: "-").last.flatMap { UInt8($0) } ?? 0),
            latitude: latitude,
            longitude: longitude,
            serverUID: serverUID,
            frequency: nil,
            lastActivity: .vocal,
            observedAt: now.addingTimeInterval(-60),
            certificateExpiresAt: now.addingTimeInterval(86_400),
            issuerSerialNumber: 1,
            trustLevel: .trusted,
            rootCRL: .notPublished,
            intermediateCRL: .notPublished
        )
    }

    private func makeServer(uid: UInt64, name: String) -> FMOV4ServerRecord {
        FMOV4ServerRecord(
            uid: uid,
            name: name,
            countryCode: "CN",
            host: "example.invalid",
            port: 1_883,
            filterKilometers: 500,
            onlineUserCount: 1,
            peakUserCount: 1,
            latitude: 0,
            longitude: 1,
            broadcasterCallsign: "BH4XYZ-15",
            observedAt: now,
            trustLevel: .trusted
        )
    }

    private func available<Value>(
        _ value: Value,
        at date: Date
    ) -> DashboardField<Value> where Value: Codable & Equatable & Sendable {
        .available(
            DashboardObservation(
                value: value,
                source: .localEventStream,
                observedAt: date,
                confidence: .trusted
            )
        )
    }
}
