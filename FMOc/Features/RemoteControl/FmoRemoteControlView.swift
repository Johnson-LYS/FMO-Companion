import SwiftUI

struct FmoRemoteControlView: View {
    @Bindable var model: FmoRemoteControlModel
    @State private var showsSettings = false
    @State private var confirmsReboot = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.target?.formatted ?? String(localized: "尚未设置"))
                            .font(.headline.monospaced())
                        Text(targetStatusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("设置") { showsSettings = true }
                        .accessibilityIdentifier("remote-control-settings")
                }
            }

            Section("运行模式") {
                commandButton(.normal, title: "正常运行", symbol: "play.circle")
                commandButton(.standby, title: "进入待机", symbol: "pause.circle")
            }

            Section {
                Button(role: .destructive) {
                    confirmsReboot = true
                } label: {
                    Label("重启设备", systemImage: "arrow.clockwise.circle")
                }
            } footer: {
                Text("每次操作只发送一次；没有收到设备确认时不会自动重试。")
            }

            if let status = statusText {
                Section("最近操作") {
                    Label(status.text, systemImage: status.symbol)
                        .foregroundStyle(status.color)
                }
            }
        }
        .navigationTitle("远程控制")
        .sheet(isPresented: $showsSettings) {
            FmoRemoteSettingsSheet(model: model)
                .presentationDetents([.medium])
        }
        .confirmationDialog(
            "确认重启这台设备？",
            isPresented: $confirmsReboot,
            titleVisibility: .visible
        ) {
            Button("重启设备", role: .destructive) {
                Task { await model.send(.reboot) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("设备会暂时离线，发送前还需通过系统身份确认。")
        }
        .alert("无法完成操作", isPresented: issueIsPresented) {
            Button("好") { model.issue = nil }
        } message: {
            Text(model.issue ?? String(localized: "请稍后再试"))
        }
    }

    private func commandButton(
        _ action: FmoRemoteAction,
        title: LocalizedStringResource,
        symbol: String
    ) -> some View {
        Button {
            Task { await model.send(action) }
        } label: {
            Label(title, systemImage: symbol)
                .fullWidthRowHitArea()
        }
        .disabled(!model.canSend || isSending)
    }

    private var isSending: Bool {
        if case .sending = model.phase { true } else { false }
    }

    private var targetStatusText: LocalizedStringResource {
        if model.canSend { return "可发送远程命令" }
        if model.isConfigured { return "等待消息网络" }
        return "设置目标与安全凭据"
    }

    private var statusText: (text: String, symbol: String, color: Color)? {
        switch model.phase {
        case .idle: nil
        case let .sending(action):
            (String(localized: "正在发送 \(actionTitle(action))"), "paperplane", .secondary)
        case let .confirmed(action):
            (String(localized: "\(actionTitle(action)) 已确认"), "checkmark.circle.fill", .green)
        case let .unconfirmed(action):
            (String(localized: "\(actionTitle(action)) 未确认，设备可能已执行"), "exclamationmark.circle", .orange)
        }
    }

    private func actionTitle(_ action: FmoRemoteAction) -> String {
        switch action {
        case .normal: String(localized: "正常运行")
        case .standby: String(localized: "进入待机")
        case .reboot: String(localized: "重启设备")
        }
    }

    private var issueIsPresented: Binding<Bool> {
        Binding(get: { model.issue != nil }, set: { if !$0 { model.issue = nil } })
    }
}

private struct FmoRemoteSettingsSheet: View {
    @Bindable var model: FmoRemoteControlModel
    @State private var target = ""
    @State private var secret = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("目标设备") {
                    TextField("呼号-SSID", text: $target)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section {
                    SecureField("12 位凭据", text: $secret)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("安全凭据")
                } footer: {
                    Text("可在 FMO 设备菜单中查看。凭据只保存在这台 iPhone。")
                }
                if model.isConfigured {
                    Section {
                        Button("移除安全凭据", role: .destructive) {
                            Task {
                                await model.removeSecret()
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("远控设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            if await model.saveSettings(target: target, secret: secret) {
                                dismiss()
                            }
                        }
                    }
                }
            }
            .onAppear { target = model.target?.formatted ?? "" }
        }
    }
}
