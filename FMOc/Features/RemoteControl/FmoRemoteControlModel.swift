import Foundation
import Observation

@MainActor
@Observable
final class FmoRemoteControlModel {
    enum Phase: Equatable {
        case idle
        case sending(FmoRemoteAction)
        case confirmed(FmoRemoteAction)
        case unconfirmed(FmoRemoteAction)
    }

    private let client: any APRSISMessaging
    private let codec: FmoRemoteControlCodec
    private let counterStore: any FmoRemoteControlCounterStoring
    private let secretStore: any FmoRemoteSecretStoring
    private let targetStore: any FmoRemoteTargetStoring
    private let authenticator: any DeviceOwnerAuthenticating
    private let now: @Sendable () -> Date
    private var timeoutTask: Task<Void, Never>?
    private var secret: String?

    var source: ReceiveOnlyAPRSIdentity?
    var target: TNC2Address?
    var phase: Phase = .idle
    var issue: String?
    private(set) var isNetworkReady = false

    init(
        client: any APRSISMessaging,
        codec: FmoRemoteControlCodec = FmoRemoteControlCodec(),
        counterStore: any FmoRemoteControlCounterStoring = UserDefaultsFmoRemoteControlCounterStore(),
        secretStore: any FmoRemoteSecretStoring = KeychainFmoRemoteSecretStore(),
        targetStore: any FmoRemoteTargetStoring = UserDefaultsFmoRemoteTargetStore(),
        authenticator: any DeviceOwnerAuthenticating = LocalDeviceOwnerAuthenticator(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.codec = codec
        self.counterStore = counterStore
        self.secretStore = secretStore
        self.targetStore = targetStore
        self.authenticator = authenticator
        self.now = now
    }

    var isConfigured: Bool { target != nil && secret != nil }
    var canSend: Bool { source != nil && isConfigured && isNetworkReady }

    func setNetworkReady(_ isReady: Bool) {
        isNetworkReady = isReady
        if !isReady, case let .sending(action) = phase {
            timeoutTask?.cancel()
            phase = .unconfirmed(action)
        }
    }

    func setSource(_ identity: ReceiveOnlyAPRSIdentity?) async {
        source = identity
        if target == nil {
            let restoredTarget = await targetStore.load()
            let defaultTarget = identity.map {
                TNC2Address(callsign: $0.callsign, ssid: $0.ssid)
            }
            if let selectedTarget = restoredTarget ?? defaultTarget {
                target = selectedTarget
                secret = try? await secretStore.load(for: selectedTarget)
            }
        }
    }

    func saveSettings(target rawTarget: String, secret rawSecret: String) async -> Bool {
        do {
            let target = try APRSMessageCodec().parseAddress(rawTarget)
            let secret = rawSecret.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard secret.utf8.count == 12, secret.utf8.allSatisfy(Self.isUppercaseASCIIAlphanumeric) else {
                issue = String(localized: "安全凭据应为 12 位大写字母或数字")
                return false
            }
            try await secretStore.save(secret, for: target)
            await targetStore.save(target)
            self.target = target
            self.secret = secret
            issue = nil
            return true
        } catch {
            issue = String(localized: "无法保存远控设置")
            return false
        }
    }

    func removeSecret() async {
        guard let target else { return }
        do {
            try await secretStore.remove(for: target)
            secret = nil
            phase = .idle
        } catch {
            issue = String(localized: "无法移除安全凭据")
        }
    }

    func send(_ action: FmoRemoteAction) async {
        guard let source else {
            issue = String(localized: "请先设置 APRS 身份")
            return
        }
        guard let target, let secret else {
            issue = String(localized: "请先完成远控设置")
            return
        }
        guard isNetworkReady else {
            issue = String(localized: "消息网络尚未连接")
            return
        }
        if action == .reboot, !(await authenticator.authorizeReboot()) {
            issue = String(localized: "未通过系统确认，未发送重启命令")
            return
        }

        do {
            let timeSlot = try codec.timeSlot(for: now())
            let sequence = await counterStore.next(for: target, timeSlot: timeSlot)
            let command = FmoRemoteCommand(
                source: TNC2Address(callsign: source.callsign, ssid: source.ssid),
                target: target,
                action: action,
                timeSlot: sequence.timeSlot,
                counter: sequence.counter
            )
            phase = .sending(action)
            try await client.send(packet: codec.encode(command, secret: secret))
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(6)) } catch { return }
                guard let self, self.phase == .sending(action) else { return }
                self.phase = .unconfirmed(action)
            }
        } catch {
            phase = .unconfirmed(action)
            issue = String(localized: "命令未发送，请确认消息网络已连接")
        }
    }

    func handleControlMessage(_ envelope: APRSMessageEnvelope) -> Bool {
        guard
            let target,
            envelope.source == target,
            case let .message(text, _) = envelope.payload,
            text.uppercased().hasPrefix("ACK,CONTROL")
        else {
            return false
        }
        if case let .sending(action) = phase {
            timeoutTask?.cancel()
            phase = .confirmed(action)
        }
        return true
    }

    private static func isUppercaseASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (48 ... 57).contains(byte) || (65 ... 90).contains(byte)
    }
}
