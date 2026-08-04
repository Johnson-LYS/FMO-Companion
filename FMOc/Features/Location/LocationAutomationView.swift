import SwiftUI
import UIKit

struct LocationAutomationView: View {
    @Bindable var model: LocationAutomationModel
    @State private var pendingMode: LocationSyncMode?
    @State private var actionTask: Task<Void, Never>?
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            statusSection
            modeSection
            activitySection
            recoverySection
        }
        .navigationTitle("位置自动化")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.restoreIfNeeded() }
        .onDisappear { actionTask?.cancel() }
        .alert(
            confirmationTitle,
            isPresented: confirmationIsPresented,
            presenting: pendingMode
        ) { mode in
            Button(String(localized: mode.enableActionTitle)) {
                pendingMode = nil
                run { await model.select(mode) }
            }
            Button("取消", role: .cancel) { pendingMode = nil }
        } message: { mode in
            Text(mode.confirmationMessage)
        }
    }

    private var statusSection: some View {
        Section("当前状态") {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
            }

            LabeledContent("定位授权") {
                Text(authorizationText)
            }
        }
    }

    private var modeSection: some View {
        Section {
            ForEach(LocationSyncMode.allCases, id: \.self) { mode in
                Button {
                    choose(mode)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: mode.symbol)
                            .foregroundStyle(model.snapshot.mode == mode ? Color.accentColor : .secondary)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(mode.title)
                                .font(.headline)
                            Text(mode.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.snapshot.mode == mode {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .foregroundStyle(.primary)
                    .fullWidthRowHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("location-mode-\(mode.rawValue)")
            }
        } header: {
            Text("同步模式")
        } footer: {
            Text("系统决定位置事件的实际交付时机；时间和距离阈值用于筛选事件，不代表严格定时。")
        }
    }

    private var activitySection: some View {
        Section("最近活动") {
            LabeledContent("最后尝试", value: lastAttemptText)
            LabeledContent("最后成功", value: formatted(model.snapshot.lastSuccessAt))
        }
    }

    @ViewBuilder
    private var recoverySection: some View {
        if needsSettingsRecovery || model.snapshot.mode != .manual {
            Section {
                if needsSettingsRecovery {
                    Button("前往系统设置", systemImage: "gear") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                }

                if isPaused, model.snapshot.mode != .manual {
                    Button("重新尝试", systemImage: "arrow.clockwise") {
                        run { await model.resume() }
                    }
                }

                if model.snapshot.mode != .manual {
                    Button("停止自动同步", systemImage: "stop.circle", role: .destructive) {
                        run { await model.stop() }
                    }
                    .accessibilityIdentifier("stop-location-automation")
                }
            } footer: {
                if needsSettingsRecovery {
                    Text("自动模式需要“始终”定位授权。App 不会保存精确坐标，停止后会取消定位、连接和重试任务。")
                } else {
                    Text("停止后会返回手动模式，并取消定位、连接和重试任务。")
                }
            }
        }
    }

    private func choose(_ mode: LocationSyncMode) {
        guard mode != model.snapshot.mode else { return }
        if mode == .manual {
            run { await model.stop() }
        } else {
            pendingMode = mode
        }
    }

    private func run(_ operation: @escaping @MainActor @Sendable () async -> Void) {
        actionTask?.cancel()
        actionTask = Task { await operation() }
    }

    private var confirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingMode != nil },
            set: { if !$0 { pendingMode = nil } }
        )
    }

    private var confirmationTitle: String {
        guard let pendingMode else { return String(localized: "启用自动同步？") }
        return String(localized: pendingMode.confirmationTitle)
    }

    private var needsSettingsRecovery: Bool {
        model.snapshot.mode != .manual
            && !model.authorization.isSufficient(for: model.snapshot.mode)
            && model.authorization != .notDetermined
    }

    private var isPaused: Bool {
        if case .paused = model.snapshot.phase { return true }
        return false
    }

    private var statusTitle: LocalizedStringResource {
        if model.snapshot.mode != .manual,
           !model.authorization.isSufficient(for: model.snapshot.mode) {
            return model.authorization == .notDetermined ? "等待定位授权" : "自动同步已暂停"
        }

        return switch model.snapshot.phase {
        case .stopped: "手动同步"
        case .starting: "正在启动自动同步"
        case .waitingForLocation: "自动同步已开启"
        case .syncing: "正在同步位置"
        case .retrying: "连接失败，正在等待重试"
        case .paused: "自动同步已暂停"
        }
    }

    private var statusMessage: LocalizedStringResource {
        if model.snapshot.mode != .manual,
           !model.authorization.isSufficient(for: model.snapshot.mode) {
            return model.authorization == .notDetermined
                ? "请完成系统提示；自动模式需要“始终”定位授权。"
                : "定位授权不足，前往系统设置允许“始终”定位后再继续。"
        }

        return switch model.snapshot.phase {
        case .stopped:
            "只有你在首页点击同步时才会更新 FMO。"
        case .starting:
            "正在建立系统定位与网络状态会话。"
        case .waitingForLocation:
            "等待符合当前模式条件的位置事件。"
        case .syncing:
            "正在把最新位置发送到已选择的 FMO。"
        case .retrying(let attempt, let delay):
            "第 \(attempt) 次重试将在约 \(delay.secondsText) 后进行。"
        case .paused(let reason):
            reason.message
        }
    }

    private var statusSymbol: String {
        switch model.snapshot.phase {
        case .stopped: "hand.tap"
        case .starting, .syncing, .retrying: "location.circle"
        case .waitingForLocation: "location.fill"
        case .paused: "pause.circle.fill"
        }
    }

    private var statusColor: Color {
        switch model.snapshot.phase {
        case .waitingForLocation: .green
        case .starting, .syncing, .retrying: .accentColor
        case .paused: .orange
        case .stopped: .secondary
        }
    }

    private var authorizationText: LocalizedStringResource {
        switch model.authorization {
        case .notDetermined: "尚未询问"
        case .whenInUse: "使用 App 期间"
        case .always: "始终允许"
        case .denied: "已拒绝"
        case .restricted: "受系统限制"
        }
    }

    private var lastAttemptText: String {
        guard let attempt = model.snapshot.lastAttempt else { return "尚无记录" }
        let result: String
        switch attempt.result {
        case .inProgress: result = "进行中"
        case .success: result = "成功"
        case .failure: result = "失败"
        }
        return "\(result) · \(formatted(attempt.timestamp))"
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "尚无记录" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private extension LocationSyncMode {
    var title: LocalizedStringResource {
        switch self {
        case .manual: "手动"
        case .lowPower: "低功耗"
        case .vehicle: "车载"
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .manual: "只在首页点击同步时更新"
        case .lowPower: "15 分钟或 1 公里 · 较省电"
        case .vehicle: "2 分钟或 250 米 · 耗电较高"
        }
    }

    var symbol: String {
        switch self {
        case .manual: "hand.tap"
        case .lowPower: "leaf"
        case .vehicle: "car"
        }
    }

    var confirmationTitle: LocalizedStringResource {
        switch self {
        case .manual: "启用手动同步？"
        case .lowPower: "启用低功耗？"
        case .vehicle: "启用车载模式？"
        }
    }

    var enableActionTitle: LocalizedStringResource {
        switch self {
        case .manual: "启用手动"
        case .lowPower: "启用低功耗"
        case .vehicle: "启用车载"
        }
    }

    var confirmationMessage: LocalizedStringResource {
        switch self {
        case .manual:
            "只在你主动操作时同步。"
        case .lowPower:
            "首次有效位置会立即同步，之后达到 15 分钟或移动 1 公里时同步。需要“始终”定位授权。"
        case .vehicle:
            "首次有效位置会立即同步，之后达到 2 分钟或移动 250 米时同步。该模式会使用更多电量，并需要“始终”定位授权。"
        }
    }
}

private extension AutomaticLocationSyncPauseReason {
    var message: LocalizedStringResource {
        switch self {
        case .networkUnavailable: "当前网络不可用；恢复后会发送内存中的最新位置。"
        case .noDevice: "尚未保存 FMO 设备；请先返回首页连接一次。"
        case .location(let reason): reason.message
        case .locationStreamFailed: "系统定位会话已中断，请重新尝试。"
        }
    }
}

private extension AutomaticLocationPauseReason {
    var message: LocalizedStringResource {
        switch self {
        case .authorizationRequestInProgress: "等待你完成系统定位授权。"
        case .authorizationDenied: "定位授权已关闭，请前往系统设置恢复。"
        case .authorizationRestricted: "定位能力受到系统限制。"
        case .alwaysAuthorizationRequired: "自动模式需要“始终”定位授权。"
        case .locationServicesDisabled: "系统定位服务当前不可用。"
        case .insufficientlyInUse: "系统暂时不允许后台定位，回到 App 后可重新尝试。"
        case .serviceSessionRequired: "系统定位会话需要重新建立。"
        case .locationUnavailable: "暂时无法取得有效位置，App 会继续等待。"
        case .stationary: "设备处于静止状态，等待新的位置事件。"
        }
    }
}

private extension Duration {
    var secondsText: String {
        let components = self.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return seconds.formatted(.number.precision(.fractionLength(0))) + " 秒"
    }
}
