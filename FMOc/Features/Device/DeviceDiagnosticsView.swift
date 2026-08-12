import SwiftUI

struct DeviceDiagnosticsView: View {
    let endpoint: FmoDeviceEndpoint?
    let isMainConnected: Bool
    @State private var model: DeviceDiagnosticsModel
    @State private var retryID = 0
    @Environment(\.dismiss) private var dismiss

    init(
        endpoint: FmoDeviceEndpoint?,
        isMainConnected: Bool,
        diagnoser: any FmoConnectionDiagnosing = FmoConnectionDiagnoser()
    ) {
        self.endpoint = endpoint
        self.isMainConnected = isMainConnected
        _model = State(initialValue: DeviceDiagnosticsModel(diagnoser: diagnoser))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("App 连接状态") {
                    Label(
                        isMainConnected
                            ? String(localized: "设备连接已建立")
                            : String(localized: "设备当前未连接"),
                        systemImage: isMainConnected ? "link.circle.fill" : "link.badge.plus"
                    )
                    .foregroundStyle(isMainConnected ? Color.green : Color.primary)

                    Text(
                        isMainConnected
                            ? String(localized: "以下结果用于独立验证当前网络路径。")
                            : String(localized: "以下结果是独立可达性检查，不代表设备页已建立连接。")
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(FmoDiagnosticStep.allCases) { step in
                        DiagnosticRow(
                            title: title(for: step),
                            detail: detail(for: step, state: model.state(for: step)),
                            suggestion: suggestion(for: model.state(for: step)),
                            status: status(for: model.state(for: step))
                        )
                    }
                } header: {
                    Text("独立探测 · \(endpoint?.displayAddress ?? "尚未选择设备")")
                } footer: {
                    Text("每一步均为独立可达性检查；全部通过表示设备可达，不等于设备页连接状态。诊断不包含精确位置、凭据或设备私密数据。")
                }
            }
            .navigationTitle("连接诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("重新检查", systemImage: "arrow.clockwise") {
                        retryID += 1
                    }
                    .disabled(endpoint == nil || model.isRunning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task(id: retryID) {
                guard let endpoint else { return }
                await model.run(endpoint: endpoint)
            }
        }
    }

    private func title(for step: FmoDiagnosticStep) -> LocalizedStringKey {
        switch step {
        case .localNetwork: "Wi-Fi / 本地网络"
        case .endpoint: "主机与端口"
        case .http: "官方 HTTP 后台"
        case .geo: "GEO WebSocket"
        }
    }

    private func detail(for step: FmoDiagnosticStep, state: FmoDiagnosticState) -> String {
        switch state {
        case .pending: String(localized: "等待检查")
        case .running: String(localized: "正在检查…")
        case .skipped: String(localized: "依赖步骤未通过")
        case .failed(let failure): failureDetail(failure)
        case .passed(let evidence):
            switch evidence {
            case .wifiAvailable: String(localized: "已检测到 Wi-Fi 接口")
            case .endpointReachable(let port): String(localized: "主机与 TCP 端口 \(port) 可达")
            case .httpResponse(let statusCode): String(localized: "收到 HTTP \(statusCode) 响应")
            case .geoResponse: String(localized: "独立握手与坐标响应正常")
            }
        }
    }

    private func failureDetail(_ failure: FmoDiagnosticFailure) -> String {
        switch failure {
        case .wifiUnavailable: String(localized: "未检测到 Wi-Fi 接口")
        case .localNetworkDenied: String(localized: "本地网络访问已关闭")
        case .resolutionFailed: String(localized: "无法解析设备主机名")
        case .endpointUnavailable: String(localized: "主机或 TCP 端口不可达")
        case .httpUnavailable: String(localized: "没有收到有效 HTTP 响应")
        case .geo(let error): error.errorDescription ?? String(localized: "GEO 检查失败")
        case .timedOut: String(localized: "检查在 5 秒后超时")
        }
    }

    private func suggestion(for state: FmoDiagnosticState) -> String? {
        guard case .failed(let failure) = state else { return nil }
        return switch failure {
        case .wifiUnavailable: String(localized: "请先让 iPhone 连接 FMO 所在的 Wi-Fi。")
        case .localNetworkDenied: String(localized: "请前往系统设置允许本地网络访问。")
        case .resolutionFailed: String(localized: "请尝试手动输入盒子的 IPv4 地址。")
        case .endpointUnavailable: String(localized: "请确认盒子在线且仍在同一局域网。")
        case .httpUnavailable: String(localized: "请在 Safari 中检查官方 fmo.local 后台。")
        case .geo(let error): error.recoverySuggestion
        case .timedOut: String(localized: "请确认网络稳定后重新检查。")
        }
    }

    private func status(for state: FmoDiagnosticState) -> DiagnosticRow.Status {
        switch state {
        case .pending, .skipped: .waiting
        case .running: .running
        case .passed: .passed
        case .failed: .failed
        }
    }
}

private struct DiagnosticRow: View {
    enum Status {
        case waiting
        case running
        case passed
        case failed
    }

    let title: LocalizedStringKey
    let detail: String
    let suggestion: String?
    let status: Status

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                if let suggestion {
                    Text(suggestion).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .running:
            ProgressView()
        default:
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
    }

    private var symbol: String {
        switch status {
        case .waiting, .running: "circle.dotted"
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch status {
        case .waiting, .running: .secondary
        case .passed: .green
        case .failed: .red
        }
    }
}
