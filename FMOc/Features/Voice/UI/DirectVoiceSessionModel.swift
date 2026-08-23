import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class DirectVoiceSessionModel {
    private let session: DirectVoiceSession
    private let identityProvider: any DirectVoiceIdentityProviding
    private let profileStore: UserDefaultsFMOServerProfileStore
    private let verifiedServerCatalogStore: UserDefaultsVerifiedFMOServerCatalogStore
    private let audioEngine: DirectVoiceAudioEngine
    private let defaults: UserDefaults
    private var stateTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?

    var snapshot = DirectVoiceSessionSnapshot()
    var identity: DirectVoiceIdentity?
    var serverProfile: FMOServerProfile?
    var verifiedServerProfiles: [FMOServerProfile]
    var isDirectTerminalSelected = false
    var isPTTExpanded = false
    var enrollmentCallsign = ""
    var enrollmentPublicKey = ""
    var importBundleText = ""
    var configurationError: String?

    init(
        session: DirectVoiceSession,
        identityProvider: any DirectVoiceIdentityProviding,
        profileStore: UserDefaultsFMOServerProfileStore,
        verifiedServerCatalogStore: UserDefaultsVerifiedFMOServerCatalogStore? = nil,
        audioEngine: DirectVoiceAudioEngine = DirectVoiceAudioEngine(),
        defaults: UserDefaults = .standard
    ) {
        self.session = session
        self.identityProvider = identityProvider
        self.profileStore = profileStore
        let resolvedCatalogStore = verifiedServerCatalogStore
            ?? UserDefaultsVerifiedFMOServerCatalogStore(defaults: defaults)
        self.verifiedServerCatalogStore = resolvedCatalogStore
        verifiedServerProfiles = resolvedCatalogStore.load()
        self.audioEngine = audioEngine
        self.defaults = defaults
        isDirectTerminalSelected = defaults.bool(forKey: "directVoiceTerminalSelected")
    }

    func restore() async {
        identity = try? await identityProvider.currentIdentity(now: .now)
        serverProfile = profileStore.load()
        stateTask?.cancel()
        stateTask = Task { [weak self, session] in
            let states = await session.states()
            for await state in states {
                guard let self else { return }
                snapshot = state
                if case .transmitting = state.phase {} else { captureTask?.cancel(); captureTask = nil }
            }
        }
        playbackTask?.cancel()
        playbackTask = Task { [weak self, session] in
            let playback = await session.playback()
            for await samples in playback {
                guard let self, !snapshot.isMuted else { continue }
                try? audioEngine.play(samples)
            }
        }
        if isDirectTerminalSelected { await session.start() }
    }

    func selectDirectTerminal() async {
        isDirectTerminalSelected = true
        defaults.set(true, forKey: "directVoiceTerminalSelected")
        await session.start()
    }

    func selectPhysicalTerminal() async {
        isDirectTerminalSelected = false
        defaults.set(false, forKey: "directVoiceTerminalSelected")
        isPTTExpanded = false
        stopCapture()
        await session.stop()
        audioEngine.stopAll()
    }

    func reconnect() async {
        await session.stop()
        if isDirectTerminalSelected { await session.start() }
    }

    func disconnect() async {
        stopCapture()
        await session.stop()
        audioEngine.stopAll()
    }

    func toggleMuted() {
        let muted = !snapshot.isMuted
        Task { await session.setMuted(muted) }
        if muted { audioEngine.stopPlayback() }
    }

    func prepareEnrollment() async {
        do {
            let request = try await identityProvider.enrollmentRequest(callsign: enrollmentCallsign)
            enrollmentCallsign = request.callsign
            enrollmentPublicKey = request.publicKeyBase64URL
            configurationError = nil
        } catch {
            configurationError = String(localized: "呼号格式不正确")
        }
    }

    func importIdentity() async {
        do {
            identity = try await identityProvider.importSignedBundle(Data(importBundleText.utf8), now: .now)
            importBundleText = ""
            configurationError = nil
            await reconnect()
        } catch {
            configurationError = String(localized: "身份包无效、已过期或与本机密钥不匹配")
        }
    }

    func saveServerProfile(_ profile: FMOServerProfile) async {
        do {
            try profileStore.save(profile)
            serverProfile = profile
            configurationError = nil
            await reconnect()
        } catch {
            configurationError = String(localized: "无法保存服务器配置")
        }
    }

    func rememberVerifiedServers(_ servers: [FMOV4ServerRecord]) {
        let merged = verifiedServerCatalogStore.merging(
            verifiedServers: servers,
            into: verifiedServerProfiles
        )
        guard merged != verifiedServerProfiles else { return }
        do {
            try verifiedServerCatalogStore.save(merged)
            verifiedServerProfiles = merged
        } catch {
            configurationError = String(localized: "无法保存已验证服务器目录")
        }
    }

    func beginTransmit() {
        guard isDirectTerminalSelected else { return }
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self else { return }
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted, !Task.isCancelled else {
                configurationError = String(localized: "请在系统设置中允许麦克风访问")
                return
            }
            do {
                try await session.beginTransmit()
                let stream = try audioEngine.startCapture()
                for await samples in stream {
                    guard !Task.isCancelled else { break }
                    await session.appendCapturedSamples(samples)
                }
            } catch {
                configurationError = String(localized: "当前无法发射，请检查连接和通道状态")
                await session.endTransmit()
                audioEngine.stopCapture()
            }
        }
    }

    func endTransmit() {
        stopCapture()
        Task { await session.endTransmit() }
    }

    func sceneBecameInactive() {
        isPTTExpanded = false
        endTransmit()
    }

    private func stopCapture() {
        captureTask?.cancel()
        captureTask = nil
        audioEngine.stopCapture()
    }
}
