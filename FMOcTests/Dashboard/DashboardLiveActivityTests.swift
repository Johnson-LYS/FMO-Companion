import Foundation
import Testing
@testable import FMOc

struct DashboardLiveActivityProjectionTests {
    @Test
    func defaultProjectionIncludesOnlyApprovedLockScreenFieldsAndFitsPayloadLimit() throws {
        let date = Date(timeIntervalSince1970: 1_754_284_800)
        let snapshot = makeSnapshot(date: date)

        let payload = DashboardLiveActivityProjection.makePayload(
            from: snapshot,
            preferences: .default,
            now: date
        )

        #expect(payload.state.connection == .connected)
        #expect(payload.state.callsign == "BG0TST")
        #expect(payload.state.serverName == "测试服务器")
        #expect(payload.state.maidenhead == nil)
        #expect(payload.state.activity?.kind == .speaking)
        #expect(payload.state.activity?.grid == nil)
        #expect(payload.staleDate == date.addingTimeInterval(15 * 60))

        let encoder = JSONEncoder()
        let staticSize = try encoder.encode(FmoDashboardActivityAttributes()).count
        let dynamicSize = try encoder.encode(payload.state).count
        #expect(staticSize + dynamicSize < 4_096)
    }

    @Test
    func privacyProjectionCanHideCallsignAndConditionallyIncludeMaidenhead() {
        let date = Date(timeIntervalSince1970: 1_754_284_800)
        let preferences = DashboardLiveActivityPreferences(
            showsCallsign: false,
            showsLocation: true
        )

        let payload = DashboardLiveActivityProjection.makePayload(
            from: makeSnapshot(date: date),
            preferences: preferences,
            now: date
        )

        #expect(payload.state.callsign == nil)
        #expect(payload.state.maidenhead == "PM01rf")
        #expect(payload.state.activity?.grid == "OM20xx")
    }

    @Test
    func disconnectedSnapshotWithCachedValuesProjectsStaleImmediately() {
        let date = Date(timeIntervalSince1970: 1_754_284_800)
        var snapshot = makeSnapshot(date: date)
        snapshot.geoLink = .disconnected
        snapshot.callsign = stale(snapshot.callsign, at: date)
        snapshot.currentServerName = stale(snapshot.currentServerName, at: date)

        let payload = DashboardLiveActivityProjection.makePayload(
            from: snapshot,
            preferences: .default,
            now: date.addingTimeInterval(30)
        )

        #expect(payload.state.connection == .stale)
        #expect(payload.state.callsign == "BG0TST")
        #expect(payload.staleDate == date.addingTimeInterval(30))
    }

    @Test
    func projectionBoundsUntrustedStringLengths() {
        let date = Date(timeIntervalSince1970: 1_754_284_800)
        var snapshot = makeSnapshot(date: date)
        snapshot.callsign = available(String(repeating: "A", count: 100), at: date)
        snapshot.currentServerName = available(String(repeating: "S", count: 500), at: date)

        let state = DashboardLiveActivityProjection.makePayload(
            from: snapshot,
            preferences: .default,
            now: date
        ).state

        #expect(state.callsign?.count == 16)
        #expect(state.serverName?.count == 64)
    }
}

@MainActor
struct DashboardLiveActivityModelTests {
    @Test
    func startsUpdatesAndEndsSingleActivity() async {
        let date = Date(timeIntervalSince1970: 1_754_284_800)
        let client = FakeDashboardLiveActivityClient()
        let store = FakeDashboardLiveActivityPreferencesStore()
        let model = DashboardLiveActivityModel(
            client: client,
            preferencesStore: store,
            dateProvider: ActivityFixedDateProvider(date: date)
        )
        let snapshot = makeSnapshot(date: date)

        await model.restore(snapshot: snapshot)
        await model.start()
        await model.receive(snapshot)
        await model.end()

        let counts = await client.counts()
        #expect(counts.starts == 1)
        #expect(counts.updates == 1)
        #expect(counts.ends == 1)
        #expect(model.phase == .inactive)
    }

    @Test
    func disabledSystemDoesNotStartActivity() async {
        let date = Date(timeIntervalSince1970: 1_754_284_800)
        let client = FakeDashboardLiveActivityClient(enabled: false)
        let model = DashboardLiveActivityModel(
            client: client,
            preferencesStore: FakeDashboardLiveActivityPreferencesStore(),
            dateProvider: ActivityFixedDateProvider(date: date)
        )

        await model.restore(snapshot: makeSnapshot(date: date))
        await model.start()

        #expect(model.phase == .unavailable)
        #expect(model.issue?.title == String(localized: "系统已关闭实时活动"))
        #expect(await client.counts().starts == 0)
    }

    @Test
    func authorizationFailureIsReportedWithoutMarkingActivityActive() async {
        let date = Date(timeIntervalSince1970: 1_754_284_800)
        let client = FakeDashboardLiveActivityClient(startError: .denied)
        let model = DashboardLiveActivityModel(
            client: client,
            preferencesStore: FakeDashboardLiveActivityPreferencesStore(),
            dateProvider: ActivityFixedDateProvider(date: date)
        )

        await model.restore(snapshot: makeSnapshot(date: date))
        await model.start()

        #expect(model.phase == .failed)
        #expect(model.issue?.title == String(localized: "实时活动权限未开启"))
        #expect(model.issue?.suggestion == String(localized: "请在“设置 > FMO 助手”中打开“实时活动”。"))
    }

    @Test
    func privacyChangesPersistAndUpdateRunningActivity() async {
        let date = Date(timeIntervalSince1970: 1_754_284_800)
        let client = FakeDashboardLiveActivityClient()
        let store = FakeDashboardLiveActivityPreferencesStore()
        let model = DashboardLiveActivityModel(
            client: client,
            preferencesStore: store,
            dateProvider: ActivityFixedDateProvider(date: date)
        )

        await model.restore(snapshot: makeSnapshot(date: date))
        await model.start()
        await model.setShowsCallsign(false)
        await model.setShowsLocation(true)

        let saved = await store.load()
        let lastPayload = await client.lastPayload()
        #expect(saved == DashboardLiveActivityPreferences(showsCallsign: false, showsLocation: true))
        #expect(lastPayload?.state.callsign == nil)
        #expect(lastPayload?.state.maidenhead == "PM01rf")
    }
}

private func makeSnapshot(date: Date) -> DashboardSnapshot {
    var snapshot = DashboardSnapshot.empty(generatedAt: date)
    snapshot.geoLink = .connected
    snapshot.localStatusLink = .connected
    snapshot.localEventLink = .connected
    snapshot.callsign = available("BG0TST", at: date)
    snapshot.currentServerName = available("测试服务器", at: date)
    snapshot.filterDistance = available(.kilometers(500), at: date)
    snapshot.maidenhead = available("PM01rf", at: date, source: .geoCoordinate, confidence: .derived)
    snapshot.qsoLogCount = available(18, at: date)
    snapshot.workingFrequencyMHz = available(438.5, at: date)
    snapshot.currentSpeaker = available(
        DashboardSpeaker(callsign: "BG1ABC", grid: "OM20xx"),
        at: date,
        source: .localEventStream
    )
    snapshot.recentLocalActivity = available(
        DashboardLocalActivity(callsign: "BG2XYZ", occurredAt: date.addingTimeInterval(-30)),
        at: date,
        source: .localEventStream
    )
    return snapshot
}

private func available<Value>(
    _ value: Value,
    at date: Date,
    source: DashboardFieldSource = .localDeviceStatus,
    confidence: DashboardConfidence = .trusted
) -> DashboardField<Value> where Value: Codable & Equatable & Sendable {
    .available(
        DashboardObservation(
            value: value,
            source: source,
            observedAt: date,
            confidence: confidence
        )
    )
}

private func stale<Value>(
    _ field: DashboardField<Value>,
    at date: Date
) -> DashboardField<Value> where Value: Codable & Equatable & Sendable {
    guard case .available(let observation) = field else { return field }
    return .stale(observation, staleAt: date)
}

private nonisolated struct ActivityFixedDateProvider: DashboardDateProviding {
    let date: Date
    func now() -> Date { date }
}

private actor FakeDashboardLiveActivityClient: DashboardLiveActivityClient {
    private let enabled: Bool
    private let startError: DashboardLiveActivityError?
    private var active = false
    private var startCount = 0
    private var updateCount = 0
    private var endCount = 0
    private var payload: DashboardLiveActivityPayload?

    init(
        enabled: Bool = true,
        startError: DashboardLiveActivityError? = nil
    ) {
        self.enabled = enabled
        self.startError = startError
    }

    func areActivitiesEnabled() -> Bool { enabled }
    func hasActiveActivity() -> Bool { active }

    func start(_ payload: DashboardLiveActivityPayload) throws {
        guard enabled else { throw DashboardLiveActivityError.disabled }
        if let startError { throw startError }
        active = true
        startCount += 1
        self.payload = payload
    }

    func update(_ payload: DashboardLiveActivityPayload) -> Bool {
        guard active else { return false }
        updateCount += 1
        self.payload = payload
        return true
    }

    func end(_ payload: DashboardLiveActivityPayload) {
        active = false
        endCount += 1
        self.payload = payload
    }

    func counts() -> (starts: Int, updates: Int, ends: Int) {
        (startCount, updateCount, endCount)
    }

    func lastPayload() -> DashboardLiveActivityPayload? { payload }
}

private actor FakeDashboardLiveActivityPreferencesStore: DashboardLiveActivityPreferencesStoring {
    private var preferences = DashboardLiveActivityPreferences.default

    func load() -> DashboardLiveActivityPreferences { preferences }
    func save(_ preferences: DashboardLiveActivityPreferences) { self.preferences = preferences }
}
