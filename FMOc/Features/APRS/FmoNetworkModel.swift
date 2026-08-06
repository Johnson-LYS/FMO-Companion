import Foundation
import Observation

nonisolated enum FmoNetworkIdentityIssue: Error, Equatable, Sendable {
    case emptyCallsign
    case invalidCallsign
    case invalidSSID
    case callsignTooLong

    var message: String {
        switch self {
        case .emptyCallsign:
            "请输入呼号。"
        case .invalidCallsign:
            "呼号需至少 3 位，且只能包含英文字母和数字。"
        case .invalidSSID:
            "设备编号需填写 0 到 15。"
        case .callsignTooLong:
            "呼号与设备编号组合后不能超过 9 个字符。"
        }
    }
}

@MainActor
@Observable
final class FmoNetworkModel {
    enum Phase: Equatable {
        case unconfigured
        case paused
        case connecting
        case receiving
        case waitingToRetry
    }

    nonisolated struct Policy: Sendable {
        var loginTimeout: Duration = .seconds(15)
        var retryDelays: [Duration] = [
            .seconds(1),
            .seconds(2),
            .seconds(4),
            .seconds(8),
            .seconds(15),
            .seconds(30),
            .seconds(60),
        ]
    }

    private enum SessionError: Error {
        case endedBeforeLogin
        case disconnected
    }

    private let receiver: any APRSISReceiving
    private let identityStore: any ReceiveOnlyAPRSIdentityStoring
    private let endpoint: APRSISEndpoint
    private let policy: Policy
    private var sessionTask: Task<Void, Never>?
    private var sessionGeneration = 0
    private var hasRestored = false
    private var isActive = false

    var configuration: ReceiveOnlyAPRSIdentityConfiguration?
    var phase: Phase = .unconfigured
    var serverCallsign: String?

    init(
        receiver: any APRSISReceiving,
        identityStore: any ReceiveOnlyAPRSIdentityStoring,
        endpoint: APRSISEndpoint = .asia,
        policy: Policy = Policy()
    ) {
        self.receiver = receiver
        self.identityStore = identityStore
        self.endpoint = endpoint
        self.policy = policy
    }

    var identity: ReceiveOnlyAPRSIdentity? {
        configuration?.identity
    }

    var statusText: String {
        switch phase {
        case .unconfigured:
            "未设置"
        case .paused:
            "已暂停"
        case .connecting:
            "正在连接"
        case .receiving:
            "正在接收"
        case .waitingToRetry:
            "等待网络"
        }
    }

    var isReceiving: Bool {
        phase == .receiving
    }

    func restoreIfNeeded(isActive: Bool) async {
        self.isActive = isActive
        if !hasRestored {
            hasRestored = true
            configuration = await identityStore.load()
        }
        await restartSession()
    }

    func setActive(_ isActive: Bool) async {
        guard self.isActive != isActive else { return }
        self.isActive = isActive
        await restartSession()
    }

    @discardableResult
    func saveManualIdentity(callsign: String, ssid: Int) async -> FmoNetworkIdentityIssue? {
        let identity: ReceiveOnlyAPRSIdentity
        do {
            identity = try ReceiveOnlyAPRSIdentity(callsign: callsign, ssid: ssid)
        } catch ReceiveOnlyAPRSIdentityError.emptyCallsign {
            return .emptyCallsign
        } catch ReceiveOnlyAPRSIdentityError.invalidCallsign {
            return .invalidCallsign
        } catch ReceiveOnlyAPRSIdentityError.invalidSSID {
            return .invalidSSID
        } catch ReceiveOnlyAPRSIdentityError.loginCallsignTooLong {
            return .callsignTooLong
        } catch {
            return .invalidCallsign
        }

        await identityStore.saveManual(identity)
        configuration = ReceiveOnlyAPRSIdentityConfiguration(
            identity: identity,
            source: .manual
        )
        await restartSession()
        return nil
    }

    func adoptTrustedFMOCallsign(_ callsign: String) async {
        guard configuration?.source != .manual else { return }
        guard let inheritedIdentity = try? ReceiveOnlyAPRSIdentity(
            callsign: callsign,
            ssid: configuration.map { Int($0.identity.ssid) } ?? 10
        ) else {
            return
        }

        guard inheritedIdentity != configuration?.identity else { return }
        await identityStore.adoptInherited(inheritedIdentity)
        configuration = ReceiveOnlyAPRSIdentityConfiguration(
            identity: inheritedIdentity,
            source: .inherited
        )
        if hasRestored {
            await restartSession()
        }
    }

    private func restartSession() async {
        sessionGeneration += 1
        let generation = sessionGeneration
        sessionTask?.cancel()
        sessionTask = nil
        await receiver.disconnect()
        serverCallsign = nil

        guard let identity else {
            phase = .unconfigured
            return
        }
        guard isActive else {
            phase = .paused
            return
        }

        phase = .connecting
        sessionTask = Task { [weak self] in
            await self?.runSession(identity: identity, generation: generation)
        }
    }

    private func runSession(identity: ReceiveOnlyAPRSIdentity, generation: Int) async {
        var retryIndex = 0

        while !Task.isCancelled, isCurrentSession(identity: identity, generation: generation) {
            phase = .connecting

            do {
                try await runAttempt(identity: identity, generation: generation)
            } catch is CancellationError {
                break
            } catch {
                guard isCurrentSession(identity: identity, generation: generation) else { break }
                phase = .waitingToRetry
            }

            guard isCurrentSession(identity: identity, generation: generation) else { break }
            guard !policy.retryDelays.isEmpty else { break }
            let delay = policy.retryDelays[min(retryIndex, policy.retryDelays.count - 1)]
            retryIndex = min(retryIndex + 1, policy.retryDelays.count - 1)
            do {
                try await Task.sleep(for: delay)
            } catch {
                break
            }
        }
    }

    private func runAttempt(
        identity: ReceiveOnlyAPRSIdentity,
        generation: Int
    ) async throws {
        let stream = await receiver.events(identity: identity, endpoint: endpoint)
        let receiver = self.receiver
        let timeout = policy.loginTimeout
        let timeoutTask = Task {
            try await Task.sleep(for: timeout)
            try Task.checkCancellation()
            await receiver.disconnect()
        }
        var becameReady = false
        defer { timeoutTask.cancel() }

        for try await event in stream {
            try Task.checkCancellation()
            guard isCurrentSession(identity: identity, generation: generation) else {
                throw CancellationError()
            }

            switch event {
            case .sessionReady(let serverCallsign):
                becameReady = true
                timeoutTask.cancel()
                self.serverCallsign = serverCallsign
                phase = .receiving
            case .frame, .rejected:
                // 未完成完整信任验证的数据只在接收层消费，不进入 UI。
                break
            }
        }

        throw becameReady ? SessionError.disconnected : SessionError.endedBeforeLogin
    }

    private func isCurrentSession(
        identity: ReceiveOnlyAPRSIdentity,
        generation: Int
    ) -> Bool {
        isActive && self.identity == identity && sessionGeneration == generation
    }
}
