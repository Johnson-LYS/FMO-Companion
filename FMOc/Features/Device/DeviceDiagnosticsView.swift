import SwiftUI

struct DeviceDiagnosticsView: View {
    let model: DeviceHomeModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DiagnosticRow(
                        title: "Wi-Fi / 本地网络",
                        detail: networkDetail,
                        status: networkStatus
                    )
                    DiagnosticRow(
                        title: "主机地址",
                        detail: model.selectedEndpoint?.displayAddress ?? "尚未选择设备",
                        status: model.selectedEndpoint == nil ? .waiting : .passed
                    )
                    DiagnosticRow(
                        title: "官方 HTTP 后台",
                        detail: "连接设备后可从这里继续检查",
                        status: .waiting
                    )
                    DiagnosticRow(
                        title: "GEO WebSocket",
                        detail: model.isConnected ? "握手与坐标响应正常" : "尚未建立连接",
                        status: model.isConnected ? .passed : .waiting
                    )
                } footer: {
                    Text("诊断不包含精确位置、凭据或设备私密数据。")
                }
            }
            .navigationTitle("连接诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var networkStatus: DiagnosticRow.Status {
        if model.isConnected || !model.endpoints.isEmpty { .passed } else { .waiting }
    }

    private var networkDetail: String {
        if model.isConnected { "本地连接可用" }
        else if model.phase == .discovering { "正在浏览 Bonjour 服务" }
        else { "开始发现后检查" }
    }
}

private struct DiagnosticRow: View {
    enum Status {
        case waiting
        case passed
        case failed
    }

    let title: LocalizedStringKey
    let detail: String
    let status: Status

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var symbol: String {
        switch status {
        case .waiting: "circle.dotted"
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch status {
        case .waiting: .secondary
        case .passed: .green
        case .failed: .red
        }
    }
}
