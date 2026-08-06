import Foundation
import Testing
@testable import FMOc

struct DashboardSnapshotTests {
    @Test
    func derivesSixCharacterMaidenheadFromGeoCoordinate() throws {
        let coordinate = try GeoCoordinate(latitude: 31.2304, longitude: 121.4737)

        #expect(MaidenheadLocator.sixCharacterGrid(for: coordinate) == "PM01rf")
    }

    @Test
    func handlesMaidenheadCoordinateBoundaries() throws {
        let origin = try GeoCoordinate(latitude: 0, longitude: 0)
        let northeastLimit = try GeoCoordinate(latitude: 90, longitude: 180)

        #expect(MaidenheadLocator.sixCharacterGrid(for: origin) == "JJ00aa")
        #expect(MaidenheadLocator.sixCharacterGrid(for: northeastLimit) == "RR99xx")
    }

    @Test
    func emptySnapshotStartsAllIndependentSourcesDisconnectedAndUnknown() {
        let snapshot = DashboardSnapshot.empty()

        #expect(snapshot.geoLink == .disconnected)
        #expect(snapshot.localStatusLink == .disconnected)
        #expect(snapshot.localEventLink == .disconnected)
        #expect(snapshot.maidenhead == .unknown)
        #expect(snapshot.callsign == .unknown)
        #expect(snapshot.currentServerName == .unknown)
        #expect(snapshot.workingFrequencyMHz == .unknown)
        #expect(snapshot.currentSpeaker == .unknown)
    }

    @Test
    func storeMakesGeoDerivedValueStaleAfterDisconnect() async throws {
        let date = Date(timeIntervalSince1970: 1_754_284_800)
        let store = DashboardStore(dateProvider: FixedDashboardDateProvider(date: date))
        let coordinate = try GeoCoordinate(latitude: 31.2304, longitude: 121.4737)

        _ = await store.beginConnection()
        let connected = await store.recordGeoCoordinate(coordinate)
        let disconnected = await store.recordGeoDisconnection()

        #expect(connected.geoLink == .connected)
        #expect(connected.maidenhead.value == "PM01rf")
        #expect(disconnected.geoLink == .disconnected)
        #expect(disconnected.maidenhead == .stale(
            DashboardObservation(
                value: "PM01rf",
                source: .geoCoordinate,
                observedAt: date,
                confidence: .derived
            ),
            staleAt: date
        ))
    }

    @Test
    func beginningAnotherConnectionDoesNotReusePreviousDeviceState() async throws {
        let date = Date(timeIntervalSince1970: 1_754_284_800)
        let store = DashboardStore(dateProvider: FixedDashboardDateProvider(date: date))
        let coordinate = try GeoCoordinate(latitude: 31.2304, longitude: 121.4737)

        _ = await store.recordGeoCoordinate(coordinate)
        let reconnecting = await store.beginConnection()

        #expect(reconnecting.geoLink == .connecting)
        #expect(reconnecting.maidenhead == .unknown)
        #expect(reconnecting.currentServerName == .unknown)
    }

    @Test
    func recordsAuthorizedLocalStatusWithoutInventingMissingFields() async {
        let date = Date(timeIntervalSince1970: 1_754_284_800)
        let store = DashboardStore(dateProvider: FixedDashboardDateProvider(date: date))
        let update = DashboardLocalStatusUpdate(
            callsign: "BG0TST",
            currentServerName: "测试服务器",
            filterDistance: .kilometers(500),
            workingFrequencyMHz: 438.5,
            qsoLogCount: nil
        )

        _ = await store.beginLocalStatusConnection()
        let snapshot = await store.recordLocalStatus(update)

        #expect(snapshot.localStatusLink == .connected)
        #expect(snapshot.callsign.currentValue == "BG0TST")
        #expect(snapshot.currentServerName.currentValue == "测试服务器")
        #expect(snapshot.filterDistance.currentValue == .kilometers(500))
        #expect(snapshot.workingFrequencyMHz.currentValue == 438.5)
        #expect(snapshot.qsoLogCount == .unknown)
    }

    @Test
    func refreshingCurrentServerPreservesOtherLocalStatusFields() async {
        let store = DashboardStore()
        let initial = DashboardLocalStatusUpdate(
            callsign: "BG0TST",
            currentServerName: "服务器 A",
            filterDistance: .kilometers(500),
            workingFrequencyMHz: 438.5,
            qsoLogCount: 18
        )

        _ = await store.recordLocalStatus(initial)
        let refreshed = await store.recordCurrentServer("服务器 B")

        #expect(refreshed.currentServerName.currentValue == "服务器 B")
        #expect(refreshed.callsign.currentValue == "BG0TST")
        #expect(refreshed.filterDistance.currentValue == .kilometers(500))
        #expect(refreshed.workingFrequencyMHz.currentValue == 438.5)
        #expect(refreshed.qsoLogCount.currentValue == 18)
    }

    @Test
    func clearsCurrentSpeakerButKeepsRecentActivityStaleWhenEventStreamEnds() async {
        let date = Date(timeIntervalSince1970: 1_754_284_800)
        let store = DashboardStore(dateProvider: FixedDashboardDateProvider(date: date))
        let speaking = FmoSpeakingState(
            callsign: "BG1ABC",
            grid: "OM20xx",
            isSpeaking: true,
            sequence: 1,
            deviceUptimeMilliseconds: 10
        )
        let activity = FmoRecentLocalActivity(callsign: "BG1ABC", occurredAt: date.addingTimeInterval(-15))

        _ = await store.recordLocalEvent(.history([activity]))
        _ = await store.recordLocalEvent(.speaking(speaking))
        let disconnected = await store.recordLocalEventDisconnection()

        #expect(disconnected.localEventLink == .disconnected)
        #expect(disconnected.currentSpeaker == .unknown)
        guard case .stale = disconnected.recentLocalActivity else {
            Issue.record("事件流断开后最近活动应保留为过期值")
            return
        }
    }

    @Test
    func replacesCurrentSpeakerWithoutRequiringAnIntermediateIdleEvent() async {
        let store = DashboardStore()
        let firstSpeaker = FmoSpeakingState(
            callsign: "BG1AAA",
            grid: "OM20aa",
            isSpeaking: true,
            sequence: 1,
            deviceUptimeMilliseconds: 10
        )
        let nextSpeaker = FmoSpeakingState(
            callsign: "BG2BBB",
            grid: "OM21bb",
            isSpeaking: true,
            sequence: 2,
            deviceUptimeMilliseconds: 20
        )

        _ = await store.recordLocalEvent(.speaking(firstSpeaker))
        let snapshot = await store.recordLocalEvent(.speaking(nextSpeaker))

        #expect(snapshot.currentSpeaker.currentValue == DashboardSpeaker(callsign: "BG2BBB", grid: "OM21bb"))
    }

    @Test
    func snapshotIsCodableAndRemainsSmallEnoughForFutureActivityProjection() async throws {
        let store = DashboardStore()
        let coordinate = try GeoCoordinate(latitude: 31.2304, longitude: 121.4737)
        let snapshot = await store.recordGeoCoordinate(coordinate)

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DashboardSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(data.count < 4_096)
    }
}

private nonisolated struct FixedDashboardDateProvider: DashboardDateProviding {
    let date: Date

    func now() -> Date { date }
}
