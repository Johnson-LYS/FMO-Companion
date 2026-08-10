import ActivityKit
import Foundation

nonisolated protocol DashboardLiveActivityClient: Sendable {
    func areActivitiesEnabled() async -> Bool
    func hasActiveActivity() async -> Bool
    func start(_ payload: DashboardLiveActivityPayload) async throws
    func update(_ payload: DashboardLiveActivityPayload) async -> Bool
    func end(_ payload: DashboardLiveActivityPayload) async
}

actor ActivityKitDashboardLiveActivityClient: DashboardLiveActivityClient {
    private var currentActivityID: String?

    func areActivitiesEnabled() -> Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func hasActiveActivity() -> Bool {
        let activities = Activity<FmoDashboardActivityAttributes>.activities.filter {
            $0.activityState.isPresented
        }
        if let activity = activities.first {
            currentActivityID = activity.id
            return true
        }
        return currentActivityID != nil
    }

    func start(_ payload: DashboardLiveActivityPayload) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw DashboardLiveActivityError.disabled
        }

        let content = activityContent(for: payload)
        let activities = Activity<FmoDashboardActivityAttributes>.activities.filter {
            $0.activityState.isPresented
        }
        if let existing = activities.first {
            await existing.update(content)
            currentActivityID = existing.id
            return
        }

        do {
            let activity = try Activity<FmoDashboardActivityAttributes>.request(
                attributes: FmoDashboardActivityAttributes(),
                content: content,
                pushType: nil,
                style: .standard
            )
            guard activity.activityState.isPresented else {
                throw DashboardLiveActivityError.notRegistered
            }
            currentActivityID = activity.id
        } catch let error as ActivityAuthorizationError {
            throw DashboardLiveActivityError(error)
        }
    }

    func update(_ payload: DashboardLiveActivityPayload) async -> Bool {
        let activities = Activity<FmoDashboardActivityAttributes>.activities.filter {
            $0.activityState.isPresented
        }
        guard !activities.isEmpty else {
            currentActivityID = nil
            return false
        }

        let content = activityContent(for: payload)
        for activity in activities {
            await activity.update(content)
        }
        currentActivityID = activities.first?.id
        return true
    }

    func end(_ payload: DashboardLiveActivityPayload) async {
        let content = activityContent(for: payload)
        for activity in Activity<FmoDashboardActivityAttributes>.activities {
            await activity.end(content, dismissalPolicy: .immediate)
        }
        currentActivityID = nil
    }

    private func activityContent(
        for payload: DashboardLiveActivityPayload
    ) -> ActivityContent<FmoDashboardActivityAttributes.ContentState> {
        ActivityContent(
            state: payload.state,
            staleDate: payload.staleDate,
            relevanceScore: payload.state.activity?.kind == .speaking ? 100 : 50
        )
    }
}

nonisolated enum DashboardLiveActivityError: LocalizedError, Equatable {
    case disabled
    case noCurrentDeviceState
    case notRegistered
    case unsupported
    case denied
    case limitReached
    case invalidConfiguration
    case persistenceFailure
    case unknownAuthorizationFailure

    init(_ error: ActivityAuthorizationError) {
        switch error {
        case .attributesTooLarge:
            self = .invalidConfiguration
        case .unsupported:
            self = .unsupported
        case .denied:
            self = .denied
        case .globalMaximumExceeded, .targetMaximumExceeded:
            self = .limitReached
        case .unsupportedTarget, .missingProcessIdentifier, .unentitled,
             .malformedActivityIdentifier, .reconnectNotPermitted:
            self = .invalidConfiguration
        case .visibility, .persistenceFailure:
            self = .persistenceFailure
        @unknown default:
            self = .unknownAuthorizationFailure
        }
    }

    var errorDescription: String? {
        switch self {
        case .disabled: String(localized: "系统已关闭实时活动")
        case .noCurrentDeviceState: String(localized: "连接 FMO 后才能开始锁屏仪表盘")
        case .notRegistered: String(localized: "系统未能登记实时活动")
        case .unsupported: String(localized: "当前设备不支持实时活动")
        case .denied: String(localized: "实时活动权限未开启")
        case .limitReached: String(localized: "实时活动数量已达系统上限")
        case .invalidConfiguration: String(localized: "实时活动配置无效")
        case .persistenceFailure: String(localized: "系统未能保存实时活动")
        case .unknownAuthorizationFailure: String(localized: "系统拒绝了实时活动请求")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .disabled: String(localized: "请在系统设置中允许 FMO Companion 使用实时活动。")
        case .noCurrentDeviceState: String(localized: "等待设备页显示呼号、服务器或动态信息后重试。")
        case .notRegistered: String(localized: "请锁屏后再次查看；若仍未显示，请重新打开 App 后重试。")
        case .unsupported: String(localized: "请使用支持实时活动的 iPhone 真机测试。")
        case .denied: String(localized: "请在“设置 > FMO Companion”中打开“实时活动”。")
        case .limitReached: String(localized: "请先结束其他 App 的部分实时活动后重试。")
        case .invalidConfiguration: String(localized: "请更新到修复后的构建版本后重试。")
        case .persistenceFailure: String(localized: "请重启设备后重试；若仍失败，请反馈当前系统版本。")
        case .unknownAuthorizationFailure: String(localized: "请确认系统设置允许实时活动后重试。")
        }
    }
}

private extension ActivityState {
    nonisolated var isPresented: Bool {
        switch self {
        case .pending, .active, .stale:
            true
        case .ended, .dismissed:
            false
        @unknown default:
            true
        }
    }
}
