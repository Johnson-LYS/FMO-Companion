import SwiftUI

struct ContentView: View {
    @State private var deviceModel: DeviceHomeModel

    init(deviceModel: DeviceHomeModel = .live()) {
        _deviceModel = State(initialValue: deviceModel)
    }

    var body: some View {
        TabView {
            Tab("首页", systemImage: "antenna.radiowaves.left.and.right") {
                NavigationStack {
                    DeviceHomeView(model: deviceModel)
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
    }
}

#Preview {
    ContentView()
}
