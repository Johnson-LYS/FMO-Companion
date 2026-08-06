import SwiftUI

struct ContentView: View {
    @State private var deviceModel: DeviceHomeModel
    @State private var locationAutomationModel: LocationAutomationModel
    @State private var officialWebModel: OfficialWebModel
    @State private var fmoNetworkModel: FmoNetworkModel
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init(models: AppComposition.Models = AppComposition.makeModels()) {
        _deviceModel = State(initialValue: models.device)
        _locationAutomationModel = State(initialValue: models.locationAutomation)
        _officialWebModel = State(initialValue: models.officialWeb)
        _fmoNetworkModel = State(initialValue: models.fmoNetwork)
    }

    var body: some View {
        TabView {
            Tab("首页", systemImage: "antenna.radiowaves.left.and.right") {
                NavigationStack {
                    DeviceHomeView(
                        model: deviceModel,
                        locationAutomationModel: locationAutomationModel,
                        officialWebModel: officialWebModel
                    )
                }
            }

            Tab("FMO 网络", systemImage: "globe.asia.australia") {
                NavigationStack {
                    FmoNetworkView(model: fmoNetworkModel)
                }
            }

            Tab("QSO", systemImage: "book.closed") {
                NavigationStack {
                    QsoHomeView()
                }
            }

            Tab("设置", systemImage: "gearshape") {
                NavigationStack {
                    SettingsHomeView()
                }
            }
        }
        .tint(.accentColor)
        .task {
            await locationAutomationModel.restoreIfNeeded()
            await fmoNetworkModel.restoreIfNeeded(isActive: scenePhase == .active)
            await adoptCurrentFMOCallsignIfAvailable()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                locationAutomationModel.refreshAuthorization()
            }
            Task {
                await fmoNetworkModel.setActive(phase == .active)
            }
        }
        .onChange(of: deviceModel.dashboardSnapshot.callsign.currentValue) { _, _ in
            Task {
                await adoptCurrentFMOCallsignIfAvailable()
            }
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
