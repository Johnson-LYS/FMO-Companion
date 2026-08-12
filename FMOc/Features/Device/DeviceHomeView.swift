import SwiftUI
import UIKit

struct DeviceHomeView: View {
    @Bindable var model: DeviceHomeModel
    @Bindable var locationAutomationModel: LocationAutomationModel
    @Bindable var officialWebModel: OfficialWebModel
    @Bindable var remoteControlModel: FmoRemoteControlModel
    let networkSnapshot: FMOV4NetworkSnapshot
    let audioClient: any FmoLocalAudioStreaming
    let dashboardSpeakerLocationStore: any DashboardSpeakerLocationStoring
    @State private var actionTask: Task<Void, Never>?
    @State private var showsDevicePicker = false
    @State private var showsDiagnostics = false
    @State private var showsFullscreenDashboard = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            statusCard
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if model.isConnected {
                coordinateSection
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            diagnosticsButton
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            deviceFeaturesSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("设备")
        .toolbar {
            if model.isConnected {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsDevicePicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.green)
                                .frame(width: 7, height: 7)
                            Text(model.selectedEndpoint?.displayName ?? "FMO")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2.bold())
                        }
                    }
                    .accessibilityLabel("选择 FMO 设备")
                    .accessibilityValue(
                        "当前设备 \(model.selectedEndpoint?.displayName ?? "FMO")，已连接"
                    )
                    .accessibilityIdentifier("dashboard-device-selector")
                }
            }
        }
        .task { await model.start() }
        .onDisappear {
            actionTask?.cancel()
            model.stopDiscovery()
        }
        .sheet(isPresented: $showsDevicePicker) {
            devicePickerSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsDiagnostics) {
            DeviceDiagnosticsView(
                endpoint: model.diagnosticEndpoint,
                isMainConnected: model.isConnected
            )
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showsFullscreenDashboard) {
            if let endpoint = model.selectedEndpoint {
                DashboardFullscreenView(
                    dashboard: model.dashboardSnapshot,
                    ownCoordinate: model.deviceCoordinate,
                    networkSnapshot: networkSnapshot,
                    deviceName: endpoint.displayName,
                    endpoint: endpoint,
                    audioClient: audioClient,
                    speakerLocationStore: dashboardSpeakerLocationStore
                )
            }
        }
        .sheet(item: $officialWebModel.destination) { destination in
            SafariView(url: destination.url)
                .ignoresSafeArea()
        }
        .alert(item: $model.issue, content: issueAlert)
        .sensoryFeedback(.success, trigger: model.phase == .success)
    }

    private var deviceFeaturesSection: some View {
        Section("设备功能") {
            NavigationLink {
                FmoRemoteControlView(model: remoteControlModel)
            } label: {
                featureRow(
                    title: "远程控制",
                    subtitle: "切换运行模式或重启设备",
                    symbol: "dot.radiowaves.up.forward",
                    showsDisclosureIndicator: false
                )
            }
            .accessibilityIdentifier("remote-control-entry")

            NavigationLink {
                LocationAutomationView(model: locationAutomationModel)
            } label: {
                featureRow(
                    title: "位置自动化",
                    subtitle: locationAutomationSubtitle,
                    symbol: "location.circle",
                    showsDisclosureIndicator: false
                )
            }
            .accessibilityIdentifier("location-automation-entry")

            Button {
                openOfficialPage(.management)
            } label: {
                featureRow(
                    title: "管理后台",
                    subtitle: "使用 FMO 官方网页管理设备",
                    symbol: "safari"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("official-management-entry")

            Button {
                openOfficialPage(.qso)
            } label: {
                featureRow(
                    title: "QSO 页面",
                    subtitle: "在 FMO 官方页面查看与导出记录",
                    symbol: "book.pages"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("official-qso-entry")
        }
        .alert(item: $officialWebModel.issue) { issue in
            Alert(
                title: Text(issue.title),
                message: Text(issue.message),
                dismissButton: .default(Text("知道了")) { officialWebModel.clearIssue() }
            )
        }
    }

    private func featureRow(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        symbol: String,
        showsDisclosureIndicator: Bool = true
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
        .fullWidthRowHitArea()
    }

    private var locationAutomationSubtitle: LocalizedStringResource {
        switch locationAutomationModel.snapshot.mode {
        case .manual: "当前为手动同步"
        case .lowPower: "低功耗模式"
        case .vehicle: "车载模式"
        }
    }

    private func openOfficialPage(_ page: FmoOfficialPage) {
        officialWebModel.open(page, endpoint: model.officialWebEndpoint)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.isConnected {
                DeviceDashboardSummaryView(
                    snapshot: model.dashboardSnapshot,
                    openFullscreen: {
                        DashboardOrientation.request(.landscape)
                        showsFullscreenDashboard = true
                    }
                )
            } else {
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

                Button(model.isDiscovering ? "查看扫描" : "选择设备") {
                    showsDevicePicker = true
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .accessibilityIdentifier("open-device-picker")
            }
        }
        .padding(20)
        .background { statusCardBackground }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var statusCardBackground: some View {
        if model.isConnected {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.11, blue: 0.13), Color(red: 0.16, green: 0.17, blue: 0.19)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(.rect(cornerRadius: 28))
        } else {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.32), Color.accentColor.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(.rect(cornerRadius: 28))
        }
    }

    private var devicePickerSheet: some View {
        NavigationStack {
            List {
                Section {
                    if model.endpoints.isEmpty {
                        ContentUnavailableView(
                            "尚未发现设备",
                            systemImage: "wifi.exclamationmark",
                            description: Text("请确认 iPhone 和 FMO 在同一 Wi-Fi。")
                        )
                        .frame(minHeight: 180)
                    } else {
                        ForEach(model.endpoints) { endpoint in
                            deviceRow(endpoint)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("删除", systemImage: "trash", role: .destructive) {
                                        run { await model.remove(endpoint) }
                                    }
                                    .labelStyle(.iconOnly)
                                    .accessibilityLabel("删除")
                                    .tint(Color(uiColor: .systemRed))
                                }
                                .contextMenu {
                                    Button("删除设备", systemImage: "trash", role: .destructive) {
                                        run { await model.remove(endpoint) }
                                    }
                                }
                                .accessibilityAction(named: Text("删除设备")) {
                                    run { await model.remove(endpoint) }
                                }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        manualAddressForm
                    } label: {
                        Label("手动输入地址", systemImage: "plus")
                            .fullWidthRowHitArea()
                    }
                    .accessibilityIdentifier("manual-address-entry")
                }
            }
            .navigationTitle("选择设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { showsDevicePicker = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(model.isDiscovering ? "停止扫描" : "重新扫描") {
                        if model.isDiscovering {
                            model.stopDiscovery()
                        } else {
                            model.startDiscovery()
                        }
                    }
                    .accessibilityIdentifier("device-discovery-toggle")
                }
            }
        }
        .accessibilityIdentifier("device-picker-sheet")
    }

    private func deviceRow(_ endpoint: FmoDeviceEndpoint) -> some View {
        Button {
            showsDevicePicker = false
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
                if model.selectedEndpoint?.id == endpoint.id, model.isConnected {
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
        .disabled(isDeviceSelectionDisabled)
        .accessibilityValue(
            model.selectedEndpoint?.id == endpoint.id && model.isConnected
                ? "当前设备，已连接"
                : "可用"
        )
        .accessibilityIdentifier("device-row-\(endpoint.id)")
    }

    private var isDeviceSelectionDisabled: Bool {
        switch model.phase {
        case .locating, .syncing: true
        default: false
        }
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

    private var manualAddressForm: some View {
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
                    showsDevicePicker = false
                    run { await model.connectManually() }
                }
                .buttonStyle(BrandPrimaryButtonStyle())
            } footer: {
                Text("通常使用 fmo.local；请不要输入 http:// 或 /ws。")
            }
        }
        .navigationTitle("手动连接")
        .navigationBarTitleDisplayMode(.inline)
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

    private var statusTitle: LocalizedStringKey {
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

    private var statusMessage: LocalizedStringKey {
        switch model.phase {
        case .idle: "在同一 Wi-Fi 中自动发现，或手动输入 fmo.local。"
        case .discovering: "系统可能会询问是否允许访问本地网络。"
        case .found: "从设备列表选择要连接的 FMO。"
        case .connecting: "正在连接 \(model.selectedEndpoint?.displayAddress ?? "FMO")。"
        case .connected: "已通过 GEO 接口连接 \(model.selectedEndpoint?.displayAddress ?? "FMO")。"
        case .locating: "位置只用于本次同步，不会上传到分析服务。"
        case .syncing: "等待盒子确认后会再次读取坐标。"
        case .success: "FMO 已更新为当前 iPhone 位置。"
        case .failure: "按提示处理后重试，手动地址始终可用。"
        }
    }

    private var statusBadge: LocalizedStringKey {
        if model.isDiscovering, !model.isConnected {
            return "扫描中"
        }
        return switch model.phase {
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
