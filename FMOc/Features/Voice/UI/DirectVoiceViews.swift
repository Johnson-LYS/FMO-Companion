import SwiftUI

struct DirectVoiceHomeCard: View {
    @Bindable var model: DirectVoiceSessionModel
    let openIdentity: () -> Void
    let openServer: () -> Void
    let openFullscreen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.identity?.callsign ?? String(localized: "APP 身份"))
                        .font(.largeTitle.bold().monospaced())
                        .foregroundStyle(.white)
                    Text(identitySubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Button(action: openIdentity) {
                    Image(systemName: "person.text.rectangle")
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 13))
                }
                .accessibilityLabel("App 身份设置")
                Button(action: openFullscreen) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 13))
                }
                .accessibilityLabel("打开横屏仪表盘")
            }

            Button(action: openServer) {
                HStack {
                    Text(model.serverProfile?.displayName ?? String(localized: "配置语音服务器"))
                        .font(.headline.bold())
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.bold())
                }
                .foregroundStyle(Color(red: 0.065, green: 0.07, blue: 0.085))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Color.accentColor, in: .rect(cornerRadius: 13))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Image(systemName: phaseSymbol)
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: isActive)
                VStack(alignment: .leading, spacing: 2) {
                    Text(phaseTitle)
                        .font(.headline)
                    if let callsign = model.snapshot.currentCallsign {
                        Text(callsign)
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
                Spacer()
                Button { model.toggleMuted() } label: {
                    Image(systemName: model.snapshot.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 13))
                }
                .accessibilityLabel("语音声音")
                .accessibilityValue(model.snapshot.isMuted ? String(localized: "已关闭") : String(localized: "已开启"))
            }
            .foregroundStyle(.white)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.11, blue: 0.13), Color(red: 0.16, green: 0.17, blue: 0.19)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 28)
        )
        .accessibilityIdentifier("direct-voice-home-card")
    }

    private var identitySubtitle: String {
        guard let identity = model.identity else { return String(localized: "生成申请并导入已签发证书") }
        return String(localized: "UID \(identity.uid) · \(Date(timeIntervalSince1970: TimeInterval(identity.expiresAt)).formatted(date: .abbreviated, time: .omitted)) 到期")
    }

    private var isActive: Bool {
        switch model.snapshot.phase { case .connecting, .receiving, .transmitting: true; default: false }
    }

    private var phaseTitle: String {
        switch model.snapshot.phase {
        case .idle: String(localized: "尚未连接")
        case .connecting: String(localized: "正在连接")
        case .listening: String(localized: "正在监听")
        case .receiving: String(localized: "正在接收")
        case .transmitting: String(localized: "正在发射")
        case .busy: String(localized: "通道繁忙")
        case .failed(let message): message
        }
    }

    private var phaseSymbol: String {
        switch model.snapshot.phase {
        case .transmitting: "mic.fill"
        case .receiving: "speaker.wave.2.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .busy: "hourglass"
        default: "antenna.radiowaves.left.and.right"
        }
    }
}

struct DirectVoiceIdentityView: View {
    @Bindable var model: DirectVoiceSessionModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let identity = model.identity {
                    Section("当前身份") {
                        LabeledContent("呼号", value: identity.callsign)
                        LabeledContent("UID", value: String(identity.uid))
                        LabeledContent("到期", value: Date(timeIntervalSince1970: TimeInterval(identity.expiresAt)).formatted(date: .long, time: .omitted))
                    }
                }
                Section {
                    TextField("呼号", text: $model.enrollmentCallsign)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("生成或读取本机公钥") { Task { await model.prepareEnrollment() } }
                    if !model.enrollmentPublicKey.isEmpty {
                        Text(model.enrollmentPublicKey)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("本机生成申请")
                } footer: {
                    Text("只把公钥交给签发管理员；私钥保存在本机 Keychain，不能导出。")
                }
                Section {
                    TextEditor(text: $model.importBundleText)
                        .font(.caption.monospaced())
                        .frame(minHeight: 150)
                    Button("验证并导入") { Task { await model.importIdentity() } }
                        .disabled(model.importBundleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("导入已签发身份包")
                } footer: {
                    Text("身份包需包含 rootCert、intermediateCert 和 userCert；不得包含私钥。")
                }
                if let error = model.configurationError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("App 身份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct DirectVoiceServerView: View {
    @Bindable var model: DirectVoiceSessionModel
    let verifiedServers: [FMOV4ServerRecord]
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var host = ""
    @State private var targetHost = ""
    @State private var port = "8883"
    @State private var uid = ""
    @State private var callsign = ""
    @State private var fingerprint = ""
    @State private var usesTLS = true
    @State private var showsManualConfiguration = false

    var body: some View {
        NavigationStack {
            Form {
                if let profile = model.serverProfile {
                    Section("当前服务器") {
                        LabeledContent(profile.displayName, value: "\(profile.dialHost):\(profile.mqttPort)")
                    }
                }

                Section {
                    if availableServers.isEmpty {
                        ContentUnavailableView(
                            "暂无已验证服务器",
                            systemImage: "server.rack",
                            description: Text("先在“FMO 网络”中接收经过证书验证的 STATION 广播，或使用下方的手动配置。")
                        )
                    } else {
                        ForEach(availableServers) { server in
                            Button {
                                select(server)
                            } label: {
                                verifiedServerRow(server)
                            }
                            .buttonStyle(.plain)
                            .disabled(UInt32(exactly: server.uid) == nil || server.certificateFingerprint.count != 32)
                            .accessibilityIdentifier("direct-voice-server-\(server.uid)")
                        }
                    }
                } header: {
                    Text("已验证服务器")
                } footer: {
                    Text("服务器身份来自已验签的 FMO V4 STATION 广播；选择后会自动填写鉴权所需字段。")
                }

                Section {
                    DisclosureGroup("手动配置（高级）", isExpanded: $showsManualConfiguration) {
                        TextField("名称", text: $displayName)
                        TextField("连接地址", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("鉴权目标域名", text: $targetHost).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("端口", text: $port).keyboardType(.numberPad)
                        TextField("服务器 UID", text: $uid).keyboardType(.numberPad)
                        TextField("服务器呼号", text: $callsign).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        TextField("服务器证书指纹（Base64url）", text: $fingerprint).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("使用 TLS", isOn: $usesTLS)
                        if !usesTLS {
                            Text("明文 MQTT 会暴露呼号、证书元数据和语音内容。")
                                .foregroundStyle(.red)
                        }
                        Button("保存手动配置", action: save)
                            .disabled(!isValid)
                    }
                }

                if let error = model.configurationError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("选择语音服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .onAppear(perform: load)
        }
    }

    private var availableServers: [FMOV4ServerRecord] {
        verifiedServers.sorted {
            if $0.countryCode != $1.countryCode { return $0.countryCode < $1.countryCode }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func verifiedServerRow(_ server: FMOV4ServerRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: server.port == 8_883 ? "lock.shield.fill" : "checkmark.shield.fill")
                .foregroundStyle(server.port == 8_883 ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(server.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(server.host):\(server.port) · UID \(server.uid)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.serverProfile?.serverUID == UInt32(exactly: server.uid) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(.rect)
    }

    private var isValid: Bool {
        !displayName.isEmpty && !host.isEmpty && !targetHost.isEmpty && UInt16(port) != nil
            && UInt32(uid) != nil && !callsign.isEmpty
            && (try? FMOV4Base64URL.decode(fingerprint, requiredByteCount: 32)) != nil
    }

    private func load() {
        guard let profile = model.serverProfile else { return }
        displayName = profile.displayName; host = profile.dialHost; targetHost = profile.targetHost
        port = String(profile.mqttPort); uid = String(profile.serverUID); callsign = profile.serverCallsign
        fingerprint = FMOV4Base64URL.encode(profile.serverCertificateFingerprint)
        usesTLS = profile.transportSecurity == .tls
    }

    private func save() {
        guard let mqttPort = UInt16(port), let serverUID = UInt32(uid),
              let fingerprintData = try? FMOV4Base64URL.decode(fingerprint, requiredByteCount: 32) else { return }
        let profile = FMOServerProfile(
            id: model.serverProfile?.id ?? UUID(), displayName: displayName,
            dialHost: host, targetHost: targetHost, mqttPort: mqttPort, serverUID: serverUID,
            serverCallsign: callsign, serverCertificateFingerprint: fingerprintData,
            role: "user", transportSecurity: usesTLS ? .tls : .plain
        )
        Task { await model.saveServerProfile(profile); dismiss() }
    }

    private func select(_ server: FMOV4ServerRecord) {
        do {
            let profile = try FMOServerProfile(
                verifiedServer: server,
                id: model.serverProfile?.id ?? UUID()
            )
            Task { await model.saveServerProfile(profile); dismiss() }
        } catch {
            model.configurationError = String(localized: "服务器身份数据不完整")
        }
    }
}

struct DirectVoiceFullscreenView: View {
    @Bindable var model: DirectVoiceSessionModel
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.065, blue: 0.08), Color(red: 0.11, green: 0.115, blue: 0.14)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    Button(action: close) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    VStack(alignment: .leading) {
                        Text(model.identity?.callsign ?? String(localized: "APP 身份")).font(.title.bold().monospaced()).foregroundStyle(Color.accentColor)
                        Text(model.serverProfile?.displayName ?? String(localized: "未配置服务器")).font(.caption).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Button { model.toggleMuted() } label: { Image(systemName: model.snapshot.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 44, height: 44) }
                }
                .foregroundStyle(.white)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(phaseHeadline).font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text(model.snapshot.currentCallsign ?? String(localized: "等待网络讲话")).font(.title.monospaced()).foregroundStyle(.white.opacity(0.58))
                        Spacer()
                    }
                    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(.white.opacity(0.045), in: .rect(cornerRadius: 24))
                    VStack(spacing: 18) {
                        Image(systemName: "waveform.path.ecg").font(.system(size: 68)).foregroundStyle(Color.accentColor)
                        Text("FMO/RAW · Opus · 前台").font(.caption.monospaced()).foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.045), in: .rect(cornerRadius: 24))
                }
            }
            .padding(16)
            SidePTTControl(model: model, isFullscreen: true)
        }
    }

    private var phaseHeadline: String {
        switch model.snapshot.phase {
        case .receiving: String(localized: "正在接收")
        case .transmitting: String(localized: "正在发射")
        case .listening: String(localized: "监听中")
        case .connecting: String(localized: "连接中")
        case .busy: String(localized: "通道繁忙")
        case .failed: String(localized: "连接失败")
        case .idle: String(localized: "未连接")
        }
    }
}
