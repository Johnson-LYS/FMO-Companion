import SwiftUI

struct ContentView: View {
    @State private var deviceModel: DeviceHomeModel
    @State private var locationAutomationModel: LocationAutomationModel
    @State private var officialWebModel: OfficialWebModel
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init(models: AppComposition.Models = AppComposition.makeModels()) {
        _deviceModel = State(initialValue: models.device)
        _locationAutomationModel = State(initialValue: models.locationAutomation)
        _officialWebModel = State(initialValue: models.officialWeb)
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
                    FmoNetworkView()
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
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                locationAutomationModel.refreshAuthorization()
            }
        }
    }
}

#Preview {
    ContentView()
}
