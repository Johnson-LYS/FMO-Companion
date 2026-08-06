import SwiftUI

struct FmoNetworkView: View {
    @Bindable var model: FmoNetworkModel
    @State private var isPresentingIdentity = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.sectionSpacing) {
                if let identity = model.identity {
                    identityBar(identity)
                    networkContent
                } else {
                    setupCard
                }
            }
            .padding(AppTheme.pageSpacing)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("FMO 网络")
        .sheet(isPresented: $isPresentingIdentity) {
            FmoNetworkIdentitySheet(
                identity: model.identity,
                save: model.saveManualIdentity
            )
        }
    }

    private var setupCard: some View {
        Button {
            isPresentingIdentity = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 4) {
                    Text("设置网络身份")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("填写呼号后即可接收 FMO 网络动态")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .fullWidthRowHitArea()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                .background.secondary,
                in: .rect(cornerRadius: 18)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("aprs-identity-setup")
    }

    private func identityBar(_ identity: ReceiveOnlyAPRSIdentity) -> some View {
        Button {
            isPresentingIdentity = true
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)

                Text(identity.loginCallsign)
                    .font(.headline.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if model.phase == .connecting {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(model.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .fullWidthRowHitArea()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                .background.secondary,
                in: .rect(cornerRadius: 18)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("aprs-session-bar")
        .accessibilityValue("\(identity.loginCallsign)，\(model.statusText)")
    }

    @ViewBuilder
    private var networkContent: some View {
        ContentUnavailableView {
            Label(contentTitle, systemImage: contentSymbol)
        } description: {
            Text(contentDescription)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .accessibilityIdentifier("aprs-network-content-state")
    }

    private var statusColor: Color {
        switch model.phase {
        case .receiving:
            .green
        case .connecting:
            .orange
        case .unconfigured, .paused, .waitingToRetry:
            .secondary
        }
    }

    private var contentTitle: LocalizedStringKey {
        switch model.phase {
        case .receiving:
            "等待网络动态"
        case .connecting:
            "正在连接"
        case .waitingToRetry:
            "网络暂不可用"
        case .paused:
            "接收已暂停"
        case .unconfigured:
            "设置网络身份"
        }
    }

    private var contentSymbol: String {
        switch model.phase {
        case .receiving:
            "dot.radiowaves.left.and.right"
        case .connecting:
            "network"
        case .waitingToRetry:
            "wifi.exclamationmark"
        case .paused:
            "pause.circle"
        case .unconfigured:
            "person.crop.circle.badge.plus"
        }
    }

    private var contentDescription: LocalizedStringKey {
        switch model.phase {
        case .receiving:
            "收到可信的台站与事件后会显示在这里。"
        case .connecting:
            "连接完成后会自动开始接收。"
        case .waitingToRetry:
            "网络恢复后会自动重连。"
        case .paused:
            "回到 App 后会自动继续接收。"
        case .unconfigured:
            "填写呼号后即可开始接收。"
        }
    }
}

private struct FmoNetworkIdentitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var callsign: String
    @State private var ssid: Int
    @State private var issue: FmoNetworkIdentityIssue?

    let save: @MainActor (String, Int) async -> FmoNetworkIdentityIssue?

    init(
        identity: ReceiveOnlyAPRSIdentity?,
        save: @escaping @MainActor (String, Int) async -> FmoNetworkIdentityIssue?
    ) {
        _callsign = State(initialValue: identity?.callsign ?? "")
        _ssid = State(initialValue: identity.map { Int($0.ssid) } ?? 10)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("呼号", text: $callsign)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("aprs-callsign-field")

                    Stepper(value: $ssid, in: 0 ... 15) {
                        LabeledContent("设备编号（SSID）", value: String(ssid))
                    }
                    .accessibilityIdentifier("aprs-ssid-stepper")
                } footer: {
                    Text("SSID 用于区分同一呼号下的不同设备。")
                }

                if let issue {
                    Section {
                        Label(issue.message, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("aprs-identity-error")
                    }
                }
            }
            .navigationTitle("网络身份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            issue = await save(callsign, ssid)
                            if issue == nil {
                                dismiss()
                            }
                        }
                    }
                    .accessibilityIdentifier("aprs-identity-save")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
