import SwiftUI
import UIKit

struct DashboardLiveActivityView: View {
    @Bindable var model: DashboardLiveActivityModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                LabeledContent {
                    Text(model.statusSubtitle)
                        .foregroundStyle(statusColor)
                        .accessibilityIdentifier("live-activity-status")
                } label: {
                    Label("实时活动", systemImage: statusSymbol)
                }
            }

            Section {
                Toggle("显示呼号", isOn: callsignBinding)
                    .accessibilityIdentifier("live-activity-callsign-toggle")
                Toggle("显示梅登黑德", isOn: locationBinding)
                    .accessibilityIdentifier("live-activity-location-toggle")
            } header: {
                Text("锁屏内容")
            } footer: {
                Text("服务器和最新动态始终按当前可信状态显示；精确坐标、频率和 QSO 列表不会进入锁屏。")
            }

            Section {
                if model.isActive {
                    Button("结束实时活动", systemImage: "stop.circle") {
                        Task { await model.end() }
                    }
                    .accessibilityIdentifier("live-activity-end")
                } else {
                    Button("显示在锁屏", systemImage: "rectangle.inset.filled.and.person.filled") {
                        Task { await model.start() }
                    }
                    .disabled(!model.canStart)
                    .accessibilityIdentifier("live-activity-start")
                }

                if !model.isSystemEnabled {
                    Button("前往系统设置", systemImage: "gear") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                }
            } footer: {
                Text("实时活动由 App 尽力更新；系统可能在后台限制更新或结束活动，不影响 FMO 连接。")
            }
        }
        .navigationTitle("锁屏仪表盘")
        .alert(item: $model.issue) { issue in
            Alert(
                title: Text(issue.title),
                message: issue.suggestion.map(Text.init),
                dismissButton: .default(Text("知道了")) { model.clearIssue() }
            )
        }
    }

    private var callsignBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.showsCallsign },
            set: { value in Task { await model.setShowsCallsign(value) } }
        )
    }

    private var locationBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.showsLocation },
            set: { value in Task { await model.setShowsLocation(value) } }
        )
    }

    private var statusSymbol: String {
        switch model.phase {
        case .active: "wave.3.right.circle.fill"
        case .starting, .ending: "arrow.trianglehead.2.clockwise.rotate.90"
        case .unavailable, .failed: "exclamationmark.circle"
        case .inactive: "lock.rectangle"
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .active: .green
        case .unavailable, .failed: .orange
        case .inactive, .starting, .ending: .secondary
        }
    }
}
