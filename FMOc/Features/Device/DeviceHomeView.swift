import SwiftUI
import UIKit

struct DeviceHomeView: View {
    @Bindable var model: DeviceHomeModel
    @State private var actionTask: Task<Void, Never>?
    @State private var showsManualAddress = false
    @State private var showsDiagnostics = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.sectionSpacing) {
                statusCard
                deviceSection

                if model.isConnected {
                    coordinateSection
                }

                diagnosticsButton
            }
            .padding(AppTheme.pageSpacing)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("首页")
        .task { await model.restoreSavedEndpoint() }
        .onDisappear { actionTask?.cancel() }
        .sheet(isPresented: $showsManualAddress) {
            manualAddressSheet
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showsDiagnostics) {
            DeviceDiagnosticsView(endpoint: model.diagnosticEndpoint)
                .presentationDetents([.medium, .large])
        }
        .alert(item: $model.issue, content: issueAlert)
        .sensoryFeedback(.success, trigger: model.phase == .success)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Image(systemName: statusSymbol)
                    .font(.title2.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.72), in: .circle)

                Spacer()

                Text(statusBadge)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.72), in: .capsule)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(statusTitle)
                    .font(.title2.bold())
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if model.isConnected {
                Button("断开连接") {
                    run { await model.disconnect() }
                }
                .buttonStyle(.bordered)
                .tint(.primary)
            } else {
                Button(model.phase == .discovering ? "正在发现…" : "发现附近的 FMO") {
                    run { await model.discover() }
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(model.isBusy)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.32), Color.accentColor.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 28)
        )
        .accessibilityElement(children: .contain)
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("设备")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("手动地址") { showsManualAddress = true }
            }

            if model.endpoints.isEmpty {
                ContentUnavailableView(
                    "尚未发现设备",
                    systemImage: "wifi.exclamationmark",
                    description: Text("请确认 iPhone 和 FMO 在同一 Wi-Fi，或使用手动地址。")
                )
                .frame(minHeight: 160)
            } else {
                ForEach(model.endpoints) { endpoint in
                    Button {
                        run { await model.connect(to: endpoint) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: endpoint.source == .bonjour ? "dot.radiowaves.left.and.right" : "keyboard")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 42, height: 42)
                                .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(endpoint.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(endpoint.displayAddress)
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.selectedEndpoint == endpoint, model.isConnected {
                                Label("已连接", systemImage: "checkmark.circle.fill")
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .fullWidthRowHitArea()
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isBusy)
                }
            }
        }
        .appCard()
    }

    private var coordinateSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("坐标同步")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("刷新盒子") {
                    run { await model.refreshDeviceCoordinate() }
                }
                .disabled(model.isBusy)
            }

            CoordinateRow(title: "FMO 坐标", coordinate: model.deviceCoordinate, symbol: "shippingbox")
            Divider()
            CoordinateRow(title: "iPhone 位置", coordinate: model.phoneLocation?.coordinate, symbol: "location")

            if let accuracy = model.phoneLocation?.horizontalAccuracy {
                Text("水平精度约 \(accuracy, format: .number.precision(.fractionLength(0))) 米")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if model.phoneLocation == nil {
                Button(model.phase == .locating ? "正在获取位置…" : "读取 iPhone 位置") {
                    run { await model.locatePhone() }
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(model.isBusy)
            } else {
                Button(model.phase == .syncing ? "正在同步…" : "同步到 FMO") {
                    run { await model.syncPhoneCoordinate() }
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(model.isBusy)
            }

            if let text = model.lastOperationText {
                Label(text, systemImage: model.phase == .success ? "checkmark.circle.fill" : "clock")
                    .font(.footnote)
                    .foregroundStyle(model.phase == .success ? Color.green : Color.secondary)
            }
        }
        .appCard()
    }

    private var diagnosticsButton: some View {
        Button {
            showsDiagnostics = true
        } label: {
            HStack {
                Label("连接诊断", systemImage: "stethoscope")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .appCard()
            .fullWidthRowHitArea()
        }
        .buttonStyle(.plain)
    }

    private var manualAddressSheet: some View {
        NavigationStack {
            Form {
                Section("FMO 地址") {
                    TextField("主机名或 IPv4", text: $model.manualHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("端口（可选）", text: $model.manualPort)
                        .keyboardType(.numberPad)
                }
                Section {
                    Button("连接") {
                        showsManualAddress = false
                        run { await model.connectManually() }
                    }
                    .buttonStyle(BrandPrimaryButtonStyle())
                } footer: {
                    Text("通常使用 fmo.local；请不要输入 http:// 或 /ws。")
                }
            }
            .navigationTitle("手动连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showsManualAddress = false }
                }
            }
        }
    }

    private func run(_ operation: @escaping @MainActor @Sendable () async -> Void) {
        actionTask?.cancel()
        actionTask = Task { await operation() }
    }

    private func issueAlert(_ issue: DeviceHomeModel.Issue) -> Alert {
        if issue.recoveryAction == .openSettings {
            return Alert(
                title: Text(issue.title),
                message: issue.suggestion.map(Text.init),
                primaryButton: .default(Text("前往设置")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                    model.clearIssue()
                },
                secondaryButton: .cancel(Text("暂不")) { model.clearIssue() }
            )
        }

        return Alert(
            title: Text(issue.title),
            message: issue.suggestion.map(Text.init),
            dismissButton: .default(Text("知道了")) { model.clearIssue() }
        )
    }

    private var statusTitle: String {
        switch model.phase {
        case .idle: "连接你的 FMO"
        case .discovering: "正在查找附近设备"
        case .found: "选择一台 FMO"
        case .connecting: "正在建立 GEO 连接"
        case .connected: "FMO 已连接"
        case .locating: "正在读取 iPhone 位置"
        case .syncing: "正在同步坐标"
        case .success: "坐标已同步"
        case .failure: "需要处理连接问题"
        }
    }

    private var statusMessage: String {
        switch model.phase {
        case .idle: "在同一 Wi-Fi 中自动发现，或手动输入 fmo.local。"
        case .discovering: "系统可能会询问是否允许访问本地网络。"
        case .found: "连接后会先读取盒子当前坐标。"
        case .connecting: "正在连接 \(model.selectedEndpoint?.displayAddress ?? "FMO")。"
        case .connected: "可以读取手机位置，并由你主动同步到盒子。"
        case .locating: "位置只用于本次同步，不会上传到分析服务。"
        case .syncing: "等待盒子确认后会再次读取坐标。"
        case .success: "FMO 已更新为当前 iPhone 位置。"
        case .failure: "按提示处理后重试，手动地址始终可用。"
        }
    }

    private var statusBadge: String {
        switch model.phase {
        case .connected, .locating, .syncing, .success: "已连接"
        case .discovering, .connecting: "进行中"
        case .failure: "需处理"
        default: "未连接"
        }
    }

    private var statusSymbol: String {
        switch model.phase {
        case .connected, .success: "checkmark.icloud.fill"
        case .discovering, .connecting, .locating, .syncing: "wave.3.right"
        case .failure: "exclamationmark.triangle.fill"
        default: "antenna.radiowaves.left.and.right"
        }
    }
}

private struct CoordinateRow: View {
    let title: LocalizedStringKey
    let coordinate: GeoCoordinate?
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let coordinate {
                    Text("\(coordinate.latitude, format: .number.precision(.fractionLength(6))), \(coordinate.longitude, format: .number.precision(.fractionLength(6)))")
                        .font(.body.monospacedDigit())
                        .textSelection(.enabled)
                } else {
                    Text("尚未读取")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}
