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
    private let fmoNetworkLocationProvider: any PhoneLocationProviding
    @Environment(\.modelContext) private var modelContext

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
    }

    var body: some View {
        TabView {
            Tab("设备", systemImage: "antenna.radiowaves.left.and.right") {
                NavigationStack {
                    DeviceHomeView(
                        model: deviceModel,
                        locationAutomationModel: locationAutomationModel,
                        officialWebModel: officialWebModel,
                        remoteControlModel: remoteControlModel
                    )
                }
            }

            Tab("FMO 网络", systemImage: "globe.asia.australia") {
                NavigationStack {
                    FmoNetworkView(
                        model: fmoNetworkModel,
                        messageModel: aprsMessageModel,
                        locationProvider: fmoNetworkLocationProvider
                    )
                }
            }

            Tab("QSO", systemImage: "book.closed") {
                NavigationStack {
                    QsoHomeView(model: qsoModel)
                }
            }

            Tab("设置", systemImage: "gearshape") {
                NavigationStack {
                    SettingsHomeView()
                }
            }
        }
        .tint(.accentColor)
        .preferredColorScheme(
            (AppAppearance(rawValue: appearanceRawValue) ?? .system).colorScheme
        )
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
