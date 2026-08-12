import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue
    @State private var deviceModel: DeviceHomeModel
    @State private var locationAutomationModel: LocationAutomationModel
    @State private var officialWebModel: OfficialWebModel
    @State private var fmoNetworkModel: FmoNetworkModel
    @State private var aprsMessageModel: APRSMessageModel
    @State private var remoteControlModel: FmoRemoteControlModel
    @State private var qsoModel: QSOModel
    @State private var dashboardHeroContext: DashboardHeroContext?
    @State private var dashboardHeroStage = DashboardHeroStage.presenting
    @State private var dashboardHeroTask: Task<Void, Never>?
    @State private var selectedTab = AppTab.device
    @State private var dashboardViewportOrientation: DashboardViewportOrientation?
    @Namespace private var dashboardHeroNamespace
    private let fmoNetworkLocationProvider: any PhoneLocationProviding
    private let audioClient: any FmoLocalAudioStreaming
    private let dashboardSpeakerLocationStore: any DashboardSpeakerLocationStoring
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @MainActor
    init(models: AppComposition.Models = AppComposition.makeModels()) {
        _deviceModel = State(initialValue: models.device)
        _locationAutomationModel = State(initialValue: models.locationAutomation)
        _officialWebModel = State(initialValue: models.officialWeb)
        _fmoNetworkModel = State(initialValue: models.fmoNetwork)
        _aprsMessageModel = State(initialValue: models.aprsMessages)
        _remoteControlModel = State(initialValue: models.remoteControl)
        _qsoModel = State(initialValue: models.qso)
        fmoNetworkLocationProvider = models.fmoNetworkLocationProvider
        audioClient = models.audioClient
        dashboardSpeakerLocationStore = models.dashboardSpeakerLocationStore
    }

    var body: some View {
        ZStack {
            mainTabs
                .toolbarVisibility(
                    hidesDashboardChrome ? .hidden : .automatic,
                    for: .tabBar
                )
                .allowsHitTesting(dashboardHeroContext == nil)
                .accessibilityHidden(dashboardHeroContext != nil)

            if dashboardHeroStage != .presenting {
                Color(red: 0.065, green: 0.07, blue: 0.085)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(9)
                    .transition(.identity)
            }

            if let context = dashboardHeroContext {
                DashboardFullscreenView(
                    dashboard: dashboardForHero(context),
                    ownCoordinate: deviceModel.deviceCoordinate,
                    networkSnapshot: fmoNetworkModel.networkSnapshot,
                    deviceName: context.deviceName,
                    endpoint: context.endpoint,
                    audioClient: audioClient,
                    speakerLocationStore: dashboardSpeakerLocationStore,
                    heroNamespace: dashboardHeroNamespace,
                    showsExpandedContent: dashboardHeroStage.showsExpandedContent,
                    activatesExpandedServices: dashboardHeroStage.activatesExpandedServices,
                    close: closeDashboardHero
                )
                .zIndex(10)
                .transition(.identity)
            }
        }
        .tint(.accentColor)
        .preferredColorScheme(
            (AppAppearance(rawValue: appearanceRawValue) ?? .system).colorScheme
        )
        .onGeometryChange(for: DashboardViewportOrientation.self) { proxy in
            DashboardViewportOrientation(size: proxy.size)
        } action: { orientation in
            handleDashboardViewportOrientation(orientation)
        }
        .task {
            locationAutomationModel.refreshAuthorization()
            await locationAutomationModel.restoreIfNeeded()
            aprsMessageModel.configure(modelContext: modelContext)
            qsoModel.configure(modelContext: modelContext)
            await qsoModel.setDevice(
                endpoint: deviceModel.selectedEndpoint,
                isConnected: deviceModel.isConnected
            )
            await fmoNetworkModel.restoreIfNeeded(isActive: true)
            await aprsMessageModel.setIdentity(fmoNetworkModel.identity)
            await aprsMessageModel.setActive(true)
            await remoteControlModel.setSource(fmoNetworkModel.identity)
            remoteControlModel.setNetworkReady(aprsMessageModel.phase == .ready)
            await adoptCurrentFMOCallsignIfAvailable()
        }
        .onDisappear {
            dashboardHeroTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            locationAutomationModel.refreshAuthorization()
            Task {
                await fmoNetworkModel.setActive(true)
                await aprsMessageModel.setActive(true)
                await qsoModel.setActive(true)
                await qsoModel.setDevice(
                    endpoint: deviceModel.selectedEndpoint,
                    isConnected: deviceModel.isConnected
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            Task {
                await fmoNetworkModel.setActive(false)
                await aprsMessageModel.setActive(false)
                await qsoModel.setActive(false)
            }
        }
        .onChange(of: deviceModel.dashboardSnapshot.callsign.currentValue) { _, _ in
            Task {
                await adoptCurrentFMOCallsignIfAvailable()
            }
        }
        .onChange(of: deviceModel.selectedEndpoint) { _, endpoint in
            if dashboardHeroContext?.endpoint != endpoint {
                closeDashboardHero()
            }
            Task {
                await qsoModel.setDevice(endpoint: endpoint, isConnected: deviceModel.isConnected)
            }
        }
        .onChange(of: deviceModel.phase) { _, _ in
            Task {
                await qsoModel.setDevice(
                    endpoint: deviceModel.selectedEndpoint,
                    isConnected: deviceModel.isConnected
                )
            }
        }
        .onChange(of: fmoNetworkModel.identity) { _, identity in
            Task {
                await aprsMessageModel.setIdentity(identity)
                await remoteControlModel.setSource(identity)
            }
        }
        .onChange(of: aprsMessageModel.phase) { _, phase in
            remoteControlModel.setNetworkReady(phase == .ready)
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("设备", systemImage: "antenna.radiowaves.left.and.right", value: .device) {
                NavigationStack {
                    DeviceHomeView(
                        model: deviceModel,
                        locationAutomationModel: locationAutomationModel,
                        officialWebModel: officialWebModel,
                        remoteControlModel: remoteControlModel,
                        dashboardHeroNamespace: dashboardHeroNamespace,
                        isDashboardHeroActive: keepsDashboardSourceHidden,
                        hidesDashboardChrome: hidesDashboardChrome,
                        openDashboardFullscreen: openDashboardHero
                    )
                }
            }

            Tab("FMO 网络", systemImage: "globe.asia.australia", value: .network) {
                NavigationStack {
                    FmoNetworkView(
                        model: fmoNetworkModel,
                        messageModel: aprsMessageModel,
                        locationProvider: fmoNetworkLocationProvider
                    )
                }
            }

            Tab("QSO", systemImage: "book.closed", value: .qso) {
                NavigationStack {
                    QsoHomeView(model: qsoModel)
                }
            }

            Tab("设置", systemImage: "gearshape", value: .settings) {
                NavigationStack {
                    SettingsHomeView()
                }
            }
        }
    }

    private func dashboardForHero(_ context: DashboardHeroContext) -> DashboardSnapshot {
        dashboardHeroStage != .presenting
            ? deviceModel.dashboardSnapshot
            : context.initialDashboard
    }

    private func openDashboardHero() {
        guard dashboardHeroContext == nil,
              let endpoint = deviceModel.selectedEndpoint,
              deviceModel.isConnected else { return }

        dashboardHeroTask?.cancel()
        dashboardHeroStage = .presenting
        withAnimation(dashboardHeroAnimation) {
            dashboardHeroContext = DashboardHeroContext(
                endpoint: endpoint,
                deviceName: endpoint.displayName,
                initialDashboard: deviceModel.dashboardSnapshot
            )
        }

        dashboardHeroTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled,
                  dashboardHeroContext != nil,
                  dashboardHeroStage == .presenting else { return }
            withAnimation(dashboardHeroAnimation) {
                dashboardHeroStage = .rotatingToLandscape
            }
            DashboardOrientation.request(.landscape)

            try? await Task.sleep(for: .milliseconds(accessibilityReduceMotion ? 160 : 430))
            guard !Task.isCancelled,
                  dashboardHeroContext != nil,
                  dashboardHeroStage == .rotatingToLandscape else { return }
            revealDashboardHeroContent()
        }
    }

    private func closeDashboardHero() {
        guard dashboardHeroContext != nil,
              dashboardHeroStage != .rotatingToPortrait else { return }

        dashboardHeroTask?.cancel()
        withAnimation(dashboardHeroAnimation) {
            dashboardHeroStage = .rotatingToPortrait
        }
        DashboardOrientation.request(.portrait)

        dashboardHeroTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(accessibilityReduceMotion ? 160 : 430))
            guard !Task.isCancelled,
                  dashboardHeroContext != nil,
                  dashboardHeroStage == .rotatingToPortrait else { return }
            dashboardHeroContext = nil
            dashboardHeroStage = .presenting
        }
    }

    private func revealDashboardHeroContent() {
        dashboardHeroTask?.cancel()
        withAnimation(.smooth(duration: 0.34, extraBounce: 0)) {
            dashboardHeroStage = .expanded
        }
    }

    private func handleDashboardViewportOrientation(
        _ orientation: DashboardViewportOrientation
    ) {
        defer { dashboardViewportOrientation = orientation }
        guard let previousOrientation = dashboardViewportOrientation,
              previousOrientation != orientation else { return }

        switch orientation {
        case .landscape:
            guard selectedTab == .device,
                  dashboardHeroContext == nil,
                  deviceModel.isConnected else { return }
            openDashboardHero()
        case .portrait:
            guard dashboardHeroContext != nil,
                  dashboardHeroStage == .expanded else { return }
            closeDashboardHero()
        }
    }

    private var dashboardHeroAnimation: Animation {
        accessibilityReduceMotion ? .easeOut(duration: 0.15) : .dashboardHero
    }

    private var hidesDashboardChrome: Bool {
        keepsDashboardSourceHidden
    }

    private var keepsDashboardSourceHidden: Bool {
        dashboardHeroContext != nil && dashboardHeroStage != .rotatingToPortrait
    }

    private func adoptCurrentFMOCallsignIfAvailable() async {
        guard
            deviceModel.dashboardSnapshot.localStatusLink == .connected,
            let callsign = deviceModel.dashboardSnapshot.callsign.currentValue
        else {
            return
        }
        await fmoNetworkModel.adoptTrustedFMOCallsign(callsign)
    }
}

#Preview {
    ContentView()
}
