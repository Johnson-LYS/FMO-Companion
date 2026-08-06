import Foundation
import Observation

nonisolated protocol DashboardLiveActivityPreferencesStoring: Sendable {
    func load() async -> DashboardLiveActivityPreferences
    func save(_ preferences: DashboardLiveActivityPreferences) async
}

actor UserDefaultsDashboardLiveActivityPreferencesStore: DashboardLiveActivityPreferencesStoring {
    private let defaults: UserDefaults
    private let key = "dashboard.live-activity.preferences"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> DashboardLiveActivityPreferences {
        guard let data = defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(DashboardLiveActivityPreferences.self, from: data) else {
            return .default
        }
        return preferences
    }

    func save(_ preferences: DashboardLiveActivityPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
@Observable
final class DashboardLiveActivityModel {
    enum Phase: Equatable {
        case inactive
        case unavailable
        case starting
        case active
        case ending
        case failed
    }

    struct Issue: Identifiable, Equatable {
        let title: String
        let suggestion: String?
        var id: String { title + (suggestion ?? "") }
    }

    private let client: any DashboardLiveActivityClient
    private let preferencesStore: any DashboardLiveActivityPreferencesStoring
    private let dateProvider: any DashboardDateProviding
    private var latestSnapshot = DashboardSnapshot.empty()

    var phase: Phase = .inactive
    var preferences = DashboardLiveActivityPreferences.default
    var issue: Issue?
    var isSystemEnabled = true

    init(
        client: any DashboardLiveActivityClient,
        preferencesStore: any DashboardLiveActivityPreferencesStoring,
        dateProvider: any DashboardDateProviding = SystemDashboardDateProvider()
    ) {
        self.client = client
        self.preferencesStore = preferencesStore
        self.dateProvider = dateProvider
    }

    var isActive: Bool { phase == .active || phase == .ending }

    var statusSubtitle: LocalizedStringResource {
        switch phase {
        case .inactive: "未开启"
        case .unavailable: "系统已关闭"
        case .starting: "正在开始"
        case .active: "正在显示"
        case .ending: "正在结束"
        case .failed: "需要处理"
        }
    }

    var canStart: Bool {
        guard isSystemEnabled, phase != .starting, phase != .ending else { return false }
        let payload = makePayload()
        return payload.state.connection == .connected && payload.hasUsefulContent
    }

    func restore(snapshot: DashboardSnapshot) async {
        latestSnapshot = snapshot
        preferences = await preferencesStore.load()
        await refreshSystemState()

        if phase == .active {
            await updateActiveActivity()
        }
    }

    func receive(_ snapshot: DashboardSnapshot) async {
        latestSnapshot = snapshot
        let hasActiveActivity: Bool
        if phase == .active {
            hasActiveActivity = true
        } else {
            hasActiveActivity = await client.hasActiveActivity()
        }
        guard hasActiveActivity else { return }
        phase = .active
        await updateActiveActivity()
    }

    func refreshSystemState() async {
        isSystemEnabled = await client.areActivitiesEnabled()
        guard isSystemEnabled else {
            phase = .unavailable
            return
        }
        phase = await client.hasActiveActivity() ? .active : .inactive
    }

    func start() async {
        issue = nil
        isSystemEnabled = await client.areActivitiesEnabled()
        guard isSystemEnabled else {
            phase = .unavailable
            present(DashboardLiveActivityError.disabled)
            return
        }

        let payload = makePayload()
        guard payload.state.connection == .connected, payload.hasUsefulContent else {
            present(DashboardLiveActivityError.noCurrentDeviceState)
            return
        }

        phase = .starting
        do {
            try await client.start(payload)
            phase = .active
        } catch {
            phase = .failed
            present(error)
        }
    }

    func end() async {
        issue = nil
        phase = .ending
        await client.end(makePayload())
        phase = .inactive
    }

    func setShowsCallsign(_ showsCallsign: Bool) async {
        preferences.showsCallsign = showsCallsign
        await savePreferencesAndUpdate()
    }

    func setShowsLocation(_ showsLocation: Bool) async {
        preferences.showsLocation = showsLocation
        await savePreferencesAndUpdate()
    }

    func clearIssue() {
        issue = nil
        if phase == .failed {
            phase = .inactive
        }
    }

    private func savePreferencesAndUpdate() async {
        await preferencesStore.save(preferences)
        if phase == .active {
            await updateActiveActivity()
        }
    }

    private func updateActiveActivity() async {
        let remainsActive = await client.update(makePayload())
        phase = remainsActive ? .active : .inactive
    }

    private func makePayload() -> DashboardLiveActivityPayload {
        DashboardLiveActivityProjection.makePayload(
            from: latestSnapshot,
            preferences: preferences,
            now: dateProvider.now()
        )
    }

    private func present(_ error: any Error) {
        let localized = error as? any LocalizedError
        issue = Issue(
            title: localized?.errorDescription ?? String(localized: "无法更新锁屏仪表盘"),
            suggestion: localized?.recoverySuggestion
        )
    }
}
