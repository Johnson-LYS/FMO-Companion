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
                        isMainConnected ? "首页连接已建立" : "首页当前未连接",
                        systemImage: isMainConnected ? "link.circle.fill" : "link.badge.plus"
                    )
                    .foregroundStyle(isMainConnected ? Color.green : Color.primary)

                    Text(
                        isMainConnected
                            ? "以下结果用于独立验证当前网络路径。"
                            : "以下结果是独立可达性检查，不代表首页已建立连接。"
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
                    Text("每一步均为独立可达性检查；全部通过表示设备可达，不等于首页连接状态。诊断不包含精确位置、凭据或设备私密数据。")
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
        case .pending: "等待检查"
        case .running: "正在检查…"
        case .skipped: "依赖步骤未通过"
        case .failed(let failure): failureDetail(failure)
        case .passed(let evidence):
            switch evidence {
            case .wifiAvailable: "已检测到 Wi-Fi 接口"
            case .endpointReachable(let port): "主机与 TCP 端口 \(port) 可达"
            case .httpResponse(let statusCode): "收到 HTTP \(statusCode) 响应"
            case .geoResponse: "独立握手与坐标响应正常"
            }
        }
    }

    private func failureDetail(_ failure: FmoDiagnosticFailure) -> String {
        switch failure {
        case .wifiUnavailable: "未检测到 Wi-Fi 接口"
        case .localNetworkDenied: "本地网络访问已关闭"
        case .resolutionFailed: "无法解析设备主机名"
        case .endpointUnavailable: "主机或 TCP 端口不可达"
        case .httpUnavailable: "没有收到有效 HTTP 响应"
        case .geo(let error): error.errorDescription ?? "GEO 检查失败"
        case .timedOut: "检查在 5 秒后超时"
        }
    }

    private func suggestion(for state: FmoDiagnosticState) -> String? {
        guard case .failed(let failure) = state else { return nil }
        return switch failure {
        case .wifiUnavailable: "请先让 iPhone 连接 FMO 所在的 Wi-Fi。"
        case .localNetworkDenied: "请前往系统设置允许本地网络访问。"
        case .resolutionFailed: "请尝试手动输入盒子的 IPv4 地址。"
        case .endpointUnavailable: "请确认盒子在线且仍在同一局域网。"
        case .httpUnavailable: "请在 Safari 中检查官方 fmo.local 后台。"
        case .geo(let error): error.recoverySuggestion
        case .timedOut: "请确认网络稳定后重新检查。"
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
