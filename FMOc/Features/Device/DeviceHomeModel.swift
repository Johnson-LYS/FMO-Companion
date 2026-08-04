import Foundation
import Observation

@MainActor
@Observable
final class DeviceHomeModel {
    enum Phase: Equatable {
        case idle
        case discovering
        case found
        case connecting
        case connected
        case locating
        case syncing
        case success
        case failure
    }

    struct Issue: Equatable, Identifiable {
        enum RecoveryAction: Equatable {
            case openSettings
        }

        let title: String
        let suggestion: String?
        let recoveryAction: RecoveryAction?
        var id: String { title + (suggestion ?? "") + String(describing: recoveryAction) }
    }

    private let discovery: any FmoDeviceDiscovering
    private let geoClient: any FmoGeoClient
    private let locationProvider: any PhoneLocationProviding
    private let endpointStore: any FmoEndpointStoring

    var phase: Phase = .idle
    var endpoints: [FmoDeviceEndpoint] = []
    var selectedEndpoint: FmoDeviceEndpoint?
    var deviceCoordinate: GeoCoordinate?
    var phoneLocation: PhoneLocationSample?
    var issue: Issue?
    var lastOperationText: String?
    var manualHost = "fmo.local"
    var manualPort = ""

    init(
        discovery: any FmoDeviceDiscovering,
        geoClient: any FmoGeoClient,
        locationProvider: any PhoneLocationProviding,
        endpointStore: any FmoEndpointStoring
    ) {
        self.discovery = discovery
        self.geoClient = geoClient
        self.locationProvider = locationProvider
        self.endpointStore = endpointStore
    }

    static func live() -> DeviceHomeModel {
        DeviceHomeModel(
            discovery: NWBrowserFmoDeviceDiscovery(),
            geoClient: FmoGeoWebSocketClient(),
            locationProvider: CoreLocationProvider(),
            endpointStore: UserDefaultsFmoEndpointStore()
        )
    }

    var isConnected: Bool {
        switch phase {
        case .connected, .locating, .syncing, .success:
            true
        default:
            false
        }
    }

    var isBusy: Bool {
        switch phase {
        case .discovering, .connecting, .locating, .syncing:
            true
        default:
            false
        }
    }

    var diagnosticEndpoint: FmoDeviceEndpoint? {
        if let selectedEndpoint { return selectedEndpoint }
        if let endpoint = endpoints.first { return endpoint }

        let portText = manualPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = portText.isEmpty ? nil : Int(portText)
        return try? FmoDeviceEndpoint(host: manualHost, port: port, source: .manual)
    }

    var officialWebEndpoint: FmoDeviceEndpoint? {
        selectedEndpoint ?? endpoints.first
    }

    func restoreSavedEndpoint() async {
        guard endpoints.isEmpty, let endpoint = await endpointStore.load() else { return }
        endpoints = [endpoint]
        selectedEndpoint = endpoint
        phase = .found
    }

    func discover() async {
        issue = nil
        phase = .discovering

        do {
            for try await endpoint in discovery.discover(timeout: .seconds(10)) {
                merge(endpoint)
                phase = .found
            }
            phase = endpoints.isEmpty ? .idle : .found
        } catch is CancellationError {
            phase = endpoints.isEmpty ? .idle : .found
        } catch {
            present(error)
        }
    }

    func connect(to endpoint: FmoDeviceEndpoint) async {
        issue = nil
        selectedEndpoint = endpoint
        phase = .connecting

        do {
            try await geoClient.connect(to: endpoint)
            deviceCoordinate = try await geoClient.getCoordinate()
            await endpointStore.save(endpoint)
            phase = .connected
            lastOperationText = "已读取 FMO 坐标"
        } catch {
            await geoClient.disconnect()
            present(error)
        }
    }

    func connectManually() async {
        do {
            let port: Int?
            if manualPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                port = nil
            } else if let value = Int(manualPort) {
                port = value
            } else {
                throw FmoDeviceEndpoint.ValidationError.invalidPort
            }

            let endpoint = merge(
                try FmoDeviceEndpoint(host: manualHost, port: port, source: .manual)
            )
            await connect(to: endpoint)
        } catch {
            present(error, fallbackTitle: "设备地址格式不正确", suggestion: "请输入主机名或 IPv4 地址，不要包含 http:// 或路径。")
        }
    }

    func refreshDeviceCoordinate() async {
        guard isConnected else { return }
        do {
            deviceCoordinate = try await geoClient.getCoordinate()
            phase = .connected
            lastOperationText = "FMO 坐标已刷新"
        } catch {
            await presentGeoOperationError(error)
        }
    }

    func locatePhone() async {
        guard isConnected else { return }
        issue = nil
        phase = .locating
        do {
            phoneLocation = try await locationProvider.currentLocation()
            phase = .connected
            lastOperationText = phoneLocation?.isAccuracyLimited == true
                ? "已获取大致位置，可由你决定是否同步"
                : "已获取 iPhone 位置"
        } catch {
            phase = .connected
            present(error, keepConnection: true)
        }
    }

    func syncPhoneCoordinate() async {
        guard isConnected else { return }
        if phoneLocation == nil { await locatePhone() }
        guard let coordinate = phoneLocation?.coordinate else { return }

        issue = nil
        phase = .syncing
        do {
            try await geoClient.setCoordinate(coordinate)
            deviceCoordinate = try await geoClient.getCoordinate()
            phase = .success
            lastOperationText = "坐标已同步，FMO 已回读确认"
        } catch {
            await presentGeoOperationError(error)
        }
    }

    func disconnect() async {
        await geoClient.disconnect()
        deviceCoordinate = nil
        phoneLocation = nil
        selectedEndpoint = nil
        lastOperationText = nil
        issue = nil
        phase = endpoints.isEmpty ? .idle : .found
    }

    func remove(_ endpoint: FmoDeviceEndpoint) async {
        let removesSelectedEndpoint = selectedEndpoint?.id == endpoint.id

        if removesSelectedEndpoint {
            await geoClient.disconnect()
            deviceCoordinate = nil
            phoneLocation = nil
            selectedEndpoint = nil
            lastOperationText = nil
            issue = nil
        }

        endpoints.removeAll { $0.id == endpoint.id }

        if let storedEndpoint = await endpointStore.load(), storedEndpoint.id == endpoint.id {
            await endpointStore.save(nil)
        }

        if removesSelectedEndpoint || !isConnected {
            phase = endpoints.isEmpty ? .idle : .found
        }
    }

    func clearIssue() {
        issue = nil
        if phase == .failure { phase = endpoints.isEmpty ? .idle : .found }
    }

    private func present(
        _ error: any Error,
        fallbackTitle: String = "操作没有完成",
        suggestion explicitSuggestion: String? = nil,
        keepConnection: Bool = false
    ) {
        let localized = error as? any LocalizedError
        issue = Issue(
            title: localized?.errorDescription ?? fallbackTitle,
            suggestion: explicitSuggestion ?? localized?.recoverySuggestion,
            recoveryAction: recoveryAction(for: error)
        )
        phase = keepConnection ? .connected : .failure
    }

    private func presentGeoOperationError(_ error: any Error) async {
        let connectionWasLost = (error as? FmoDeviceError) == .disconnected
        if connectionWasLost {
            await geoClient.disconnect()
            deviceCoordinate = nil
            lastOperationText = nil
        }
        present(error, keepConnection: !connectionWasLost)
    }

    private func recoveryAction(for error: any Error) -> Issue.RecoveryAction? {
        if (error as? FmoDeviceError) == .localNetworkDenied {
            return .openSettings
        }
        if (error as? PhoneLocationError) == .denied {
            return .openSettings
        }
        return nil
    }

    @discardableResult
    private func merge(_ endpoint: FmoDeviceEndpoint) -> FmoDeviceEndpoint {
        if let existingEndpoint = endpoints.first(where: { $0.id == endpoint.id }) {
            return existingEndpoint
        }
        endpoints.append(endpoint)
        return endpoint
    }
}
