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
    private let localStatusProvider: any FmoLocalStatusProviding
    private let localEventStream: any FmoLocalEventStreaming
    private let locationProvider: any PhoneLocationProviding
    private let endpointStore: any FmoEndpointStoring
    private let dashboardStore: DashboardStore
    private var discoveryTask: Task<Void, Never>?
    private var discoveryID: UUID?
    private var automaticConnectionEligible = false
    private var connectionAttemptID = 0
    private var connectionTask: Task<Void, Never>?
    private var localEventTask: Task<Void, Never>?

    var phase: Phase = .idle
    var endpoints: [FmoDeviceEndpoint] = []
    var selectedEndpoint: FmoDeviceEndpoint?
    var deviceCoordinate: GeoCoordinate?
    var phoneLocation: PhoneLocationSample?
    var issue: Issue?
    var lastOperationText: String?
    var dashboardSnapshot = DashboardSnapshot.empty()
    var manualHost = "fmo.local"
    var manualPort = ""
    var isDiscovering = false

    init(
        discovery: any FmoDeviceDiscovering,
        geoClient: any FmoGeoClient,
        localStatusProvider: any FmoLocalStatusProviding = UnavailableFmoLocalStatusProvider(),
        localEventStream: any FmoLocalEventStreaming = UnavailableFmoLocalEventStream(),
        locationProvider: any PhoneLocationProviding,
        endpointStore: any FmoEndpointStoring,
        dashboardStore: DashboardStore = DashboardStore()
    ) {
        self.discovery = discovery
        self.geoClient = geoClient
        self.localStatusProvider = localStatusProvider
        self.localEventStream = localEventStream
        self.locationProvider = locationProvider
        self.endpointStore = endpointStore
        self.dashboardStore = dashboardStore
    }

    static func live() -> DeviceHomeModel {
        DeviceHomeModel(
            discovery: NWBrowserFmoDeviceDiscovery(),
            geoClient: FmoGeoWebSocketClient(),
            localStatusProvider: FmoLocalStatusWebSocketClient(),
            localEventStream: FmoLocalEventWebSocketClient(),
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

    func start() async {
        await restoreSavedEndpoint()
        startDiscovery()
    }

    func restoreSavedEndpoint() async {
        guard endpoints.isEmpty, let endpoint = await endpointStore.load() else { return }
        endpoints = [endpoint]
        selectedEndpoint = endpoint
        phase = .found
    }

    func startDiscovery() {
        guard discoveryTask == nil else { return }

        let id = UUID()
        discoveryID = id
        automaticConnectionEligible = !isConnected && phase != .connecting
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            await self.performDiscovery(id: id)
        }
    }

    func stopDiscovery() {
        automaticConnectionEligible = false
        discoveryTask?.cancel()
    }

    func waitForDiscovery() async {
        await discoveryTask?.value
    }

    private func performDiscovery(id: UUID) async {
        issue = nil
        isDiscovering = true
        if !isConnected, phase != .connecting {
            phase = .discovering
        }

        defer {
            if discoveryID == id {
                discoveryTask = nil
                discoveryID = nil
                automaticConnectionEligible = false
                isDiscovering = false
                if phase == .discovering {
                    phase = endpoints.isEmpty ? .idle : .found
                }
            }
        }

        do {
            for try await endpoint in discovery.discover(timeout: .seconds(10)) {
                try Task.checkCancellation()
                let candidate = merge(endpoint)

                if phase == .discovering {
                    phase = .found
                }

                if automaticConnectionEligible {
                    automaticConnectionEligible = false
                    startAutomaticConnection(to: candidate)
                }
            }
        } catch is CancellationError {
        } catch {
            if !isConnected, phase != .connecting {
                present(error)
            }
        }
    }

    func connect(to endpoint: FmoDeviceEndpoint) async {
        guard !isCurrentOrConnecting(endpoint) else { return }
        automaticConnectionEligible = false
        await launchConnection(to: endpoint).value
    }

    func waitForConnection() async {
        await connectionTask?.value
    }

    private func startAutomaticConnection(to endpoint: FmoDeviceEndpoint) {
        guard !isCurrentOrConnecting(endpoint) else { return }
        launchConnection(to: endpoint)
    }

    @discardableResult
    private func launchConnection(to endpoint: FmoDeviceEndpoint) -> Task<Void, Never> {
        connectionAttemptID += 1
        let attemptID = connectionAttemptID
        connectionTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performConnection(to: endpoint, attemptID: attemptID)
            if self.connectionAttemptID == attemptID {
                self.connectionTask = nil
            }
        }
        connectionTask = task
        return task
    }

    private func performConnection(to endpoint: FmoDeviceEndpoint, attemptID: Int) async {
        let replacesActiveConnection = selectedEndpoint != nil && (isConnected || phase == .connecting)

        await stopLocalConnections()
        if replacesActiveConnection {
            await geoClient.disconnect()
        }
        guard attemptID == connectionAttemptID, !Task.isCancelled else { return }

        issue = nil
        selectedEndpoint = endpoint
        phase = .connecting
        dashboardSnapshot = await dashboardStore.beginConnection()

        do {
            try await geoClient.connect(to: endpoint)
            guard attemptID == connectionAttemptID, !Task.isCancelled else { return }
            let coordinate = try await geoClient.getCoordinate()
            guard attemptID == connectionAttemptID, !Task.isCancelled else { return }
            deviceCoordinate = coordinate
            dashboardSnapshot = await dashboardStore.recordGeoCoordinate(coordinate)
            await endpointStore.save(endpoint)
            guard attemptID == connectionAttemptID, !Task.isCancelled else { return }
            phase = .connected
            lastOperationText = "已读取 FMO 坐标"
            await refreshLocalStatus(from: endpoint)
            guard attemptID == connectionAttemptID, !Task.isCancelled else { return }
            startLocalEvents(from: endpoint)
        } catch {
            guard attemptID == connectionAttemptID else { return }
            await geoClient.disconnect()
            dashboardSnapshot = await dashboardStore.recordGeoDisconnection()
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
            let coordinate = try await geoClient.getCoordinate()
            deviceCoordinate = coordinate
            dashboardSnapshot = await dashboardStore.recordGeoCoordinate(coordinate)
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
            let confirmedCoordinate = try await geoClient.getCoordinate()
            deviceCoordinate = confirmedCoordinate
            dashboardSnapshot = await dashboardStore.recordGeoCoordinate(confirmedCoordinate)
            phase = .success
            lastOperationText = "坐标已同步，FMO 已回读确认"
        } catch {
            await presentGeoOperationError(error)
        }
    }

    func disconnect() async {
        cancelConnectionAttempt()
        await stopLocalConnections()
        await geoClient.disconnect()
        deviceCoordinate = nil
        phoneLocation = nil
        selectedEndpoint = nil
        lastOperationText = nil
        issue = nil
        dashboardSnapshot = await dashboardStore.recordGeoDisconnection()
        dashboardSnapshot = await dashboardStore.recordLocalStatusDisconnection()
        dashboardSnapshot = await dashboardStore.recordLocalEventDisconnection()
        phase = endpoints.isEmpty ? .idle : .found
    }

    func remove(_ endpoint: FmoDeviceEndpoint) async {
        let removesSelectedEndpoint = selectedEndpoint?.id == endpoint.id

        if removesSelectedEndpoint {
            cancelConnectionAttempt()
            await stopLocalConnections()
            await geoClient.disconnect()
            deviceCoordinate = nil
            phoneLocation = nil
            selectedEndpoint = nil
            lastOperationText = nil
            issue = nil
            dashboardSnapshot = await dashboardStore.reset()
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
            await stopLocalConnections()
            await geoClient.disconnect()
            deviceCoordinate = nil
            lastOperationText = nil
            dashboardSnapshot = await dashboardStore.recordGeoDisconnection()
            dashboardSnapshot = await dashboardStore.recordLocalStatusDisconnection()
            dashboardSnapshot = await dashboardStore.recordLocalEventDisconnection()
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

    private func isCurrentOrConnecting(_ endpoint: FmoDeviceEndpoint) -> Bool {
        selectedEndpoint?.id == endpoint.id && (isConnected || phase == .connecting)
    }

    private func cancelConnectionAttempt() {
        connectionAttemptID += 1
        connectionTask?.cancel()
        connectionTask = nil
    }

    private func refreshLocalStatus(from endpoint: FmoDeviceEndpoint) async {
        dashboardSnapshot = await dashboardStore.beginLocalStatusConnection()

        do {
            try await localStatusProvider.connect(to: endpoint)
        } catch {
            dashboardSnapshot = await dashboardStore.recordLocalStatusDisconnection()
            return
        }

        var update = DashboardLocalStatusUpdate()

        if let value = try? await localStatusProvider.getCallsign() {
            update.callsign = value
        }
        if let value = try? await localStatusProvider.getCurrentServer() {
            update.currentServerName = value.name
        }
        if let value = try? await localStatusProvider.getServerFilter() {
            switch value {
            case .disabled: update.filterDistance = .disabled
            case .kilometers(let kilometers): update.filterDistance = .kilometers(kilometers)
            }
        }
        if let value = try? await localStatusProvider.getWorkingFrequencyMHz() {
            update.workingFrequencyMHz = value
        }
        if let value = try? await localStatusProvider.getQSOLogCount() {
            update.qsoLogCount = value
        }

        dashboardSnapshot = update.availableFieldCount > 0
            ? await dashboardStore.recordLocalStatus(update)
            : await dashboardStore.recordLocalStatusDisconnection()
    }

    private func startLocalEvents(from endpoint: FmoDeviceEndpoint) {
        localEventTask?.cancel()
        localEventTask = Task { [weak self] in
            guard let self else { return }
            dashboardSnapshot = await dashboardStore.beginLocalEventConnection()
            let stream = await localEventStream.events(from: endpoint)

            do {
                for try await event in stream {
                    guard !Task.isCancelled, selectedEndpoint?.id == endpoint.id else { return }
                    dashboardSnapshot = await dashboardStore.recordLocalEvent(event)
                }
                guard !Task.isCancelled, selectedEndpoint?.id == endpoint.id else { return }
                dashboardSnapshot = await dashboardStore.recordLocalEventDisconnection()
            } catch {
                guard !Task.isCancelled, selectedEndpoint?.id == endpoint.id else { return }
                dashboardSnapshot = await dashboardStore.recordLocalEventDisconnection()
            }
        }
    }

    private func stopLocalConnections() async {
        localEventTask?.cancel()
        localEventTask = nil
        await localEventStream.disconnect()
        await localStatusProvider.disconnect()
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
