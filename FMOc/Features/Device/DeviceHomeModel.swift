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
    private let statusRefreshWaiter: any FmoStatusRefreshWaiting
    private let currentServerRefreshInterval: Duration
    private var discoveryTask: Task<Void, Never>?
    private var discoveryID: UUID?
    private var hasStarted = false
    private var automaticConnectionEnabled = false
    private var automaticConnectionCycleID = 0
    private var automaticConnectionQueue: [FmoDeviceEndpoint] = []
    private var attemptedAutomaticEndpointIDs = Set<String>()
    private var lastAutomaticConnectionError: (any Error)?
    private var lastSuccessfulEndpointID: String?
    private var connectionAttemptID = 0
    private var connectionTask: Task<Void, Never>?
    private var localStatusTask: Task<Void, Never>?
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
        dashboardStore: DashboardStore = DashboardStore(),
        statusRefreshWaiter: any FmoStatusRefreshWaiting = TaskFmoStatusRefreshWaiter(),
        currentServerRefreshInterval: Duration = .seconds(3)
    ) {
        self.discovery = discovery
        self.geoClient = geoClient
        self.localStatusProvider = localStatusProvider
        self.localEventStream = localEventStream
        self.locationProvider = locationProvider
        self.endpointStore = endpointStore
        self.dashboardStore = dashboardStore
        self.statusRefreshWaiter = statusRefreshWaiter
        self.currentServerRefreshInterval = currentServerRefreshInterval
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
        guard !hasStarted else {
            startDiscovery()
            return
        }

        hasStarted = true
        let savedEndpoints = await restoreSavedEndpoints()
        beginAutomaticConnectionCycle(with: savedEndpoints)
        startDiscovery()
        startAutomaticConnectionQueueIfNeeded()
    }

    @discardableResult
    func restoreSavedEndpoints() async -> [FmoDeviceEndpoint] {
        guard endpoints.isEmpty else { return endpoints }
        let registry = await endpointStore.loadRegistry()
        endpoints = registry.endpoints
        lastSuccessfulEndpointID = registry.lastSuccessfulEndpointID
        selectedEndpoint = registry.lastSuccessfulEndpoint
        guard !endpoints.isEmpty else { return [] }
        phase = .found
        return endpoints
    }

    func startDiscovery() {
        guard discoveryTask == nil else { return }

        issue = nil
        isDiscovering = true
        if !isConnected, phase != .connecting {
            phase = .discovering
        }

        let id = UUID()
        discoveryID = id
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            await self.performDiscovery(id: id)
        }
    }

    func stopDiscovery() {
        discoveryTask?.cancel()
    }

    func waitForDiscovery() async {
        await discoveryTask?.value
    }

    private func performDiscovery(id: UUID) async {
        defer {
            if discoveryID == id {
                discoveryTask = nil
                discoveryID = nil
                isDiscovering = false
                if phase == .discovering {
                    phase = endpoints.isEmpty ? .idle : .found
                }
                finishAutomaticConnectionIfExhausted()
            }
        }

        do {
            for try await endpoint in discovery.discover(timeout: .seconds(10)) {
                try Task.checkCancellation()
                let (mergedEndpoint, inserted) = merge(endpoint)
                if inserted {
                    await persistEndpointRegistry()
                    enqueueAutomaticConnection(mergedEndpoint)
                }

                if phase == .discovering {
                    phase = .found
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
        let (mergedEndpoint, inserted) = merge(endpoint)
        if inserted { await persistEndpointRegistry() }
        guard !isCurrentOrConnecting(mergedEndpoint) else { return }
        cancelAutomaticConnectionCycle()
        await launchConnection(to: mergedEndpoint).value
    }

    func waitForConnection() async {
        await connectionTask?.value
    }

    @discardableResult
    private func launchConnection(to endpoint: FmoDeviceEndpoint) -> Task<Void, Never> {
        connectionAttemptID += 1
        let attemptID = connectionAttemptID
        connectionTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            _ = await self.performConnection(
                to: endpoint,
                attemptID: attemptID,
                presentsFailure: true
            )
            if self.connectionAttemptID == attemptID {
                self.connectionTask = nil
            }
        }
        connectionTask = task
        return task
    }

    @discardableResult
    private func performConnection(
        to endpoint: FmoDeviceEndpoint,
        attemptID: Int,
        presentsFailure: Bool
    ) async -> Bool {
        let replacesActiveConnection = selectedEndpoint != nil && (isConnected || phase == .connecting)

        await stopLocalConnections()
        if replacesActiveConnection {
            await geoClient.disconnect()
        }
        guard attemptID == connectionAttemptID, !Task.isCancelled else { return false }

        issue = nil
        selectedEndpoint = endpoint
        phase = .connecting
        dashboardSnapshot = await dashboardStore.beginConnection()

        do {
            try await geoClient.connect(to: endpoint)
            guard attemptID == connectionAttemptID, !Task.isCancelled else { return false }
            let coordinate = try await geoClient.getCoordinate()
            guard attemptID == connectionAttemptID, !Task.isCancelled else { return false }
            deviceCoordinate = coordinate
            dashboardSnapshot = await dashboardStore.recordGeoCoordinate(coordinate)
            markSuccessful(endpoint)
            await persistEndpointRegistry()
            guard attemptID == connectionAttemptID, !Task.isCancelled else { return false }
            phase = .connected
            lastOperationText = nil
            let hasCurrentServer = await refreshLocalStatus(from: endpoint)
            guard attemptID == connectionAttemptID, !Task.isCancelled else { return false }
            startLocalStatusRefresh(from: endpoint, requiresFullSnapshot: !hasCurrentServer)
            startLocalEvents(from: endpoint)
            return true
        } catch {
            guard attemptID == connectionAttemptID else { return false }
            await geoClient.disconnect()
            dashboardSnapshot = await dashboardStore.recordGeoDisconnection()
            if presentsFailure {
                present(error)
            } else {
                lastAutomaticConnectionError = error
                issue = nil
                phase = isDiscovering ? .discovering : (endpoints.isEmpty ? .idle : .found)
            }
            return false
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

            let endpoint = try FmoDeviceEndpoint(host: manualHost, port: port, source: .manual)
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
            cancelAutomaticConnectionCycle()
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
        automaticConnectionQueue.removeAll { $0.id == endpoint.id }
        attemptedAutomaticEndpointIDs.remove(endpoint.id)
        if lastSuccessfulEndpointID == endpoint.id { lastSuccessfulEndpointID = nil }
        await persistEndpointRegistry()

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

    private func beginAutomaticConnectionCycle(with candidates: [FmoDeviceEndpoint]) {
        automaticConnectionCycleID += 1
        automaticConnectionEnabled = true
        automaticConnectionQueue = FmoEndpointRegistry(
            endpoints: candidates,
            lastSuccessfulEndpointID: lastSuccessfulEndpointID
        ).endpoints
        attemptedAutomaticEndpointIDs = []
        lastAutomaticConnectionError = nil
    }

    private func enqueueAutomaticConnection(_ endpoint: FmoDeviceEndpoint) {
        guard automaticConnectionEnabled,
              !isConnected,
              !attemptedAutomaticEndpointIDs.contains(endpoint.id),
              !automaticConnectionQueue.contains(where: { $0.id == endpoint.id }) else {
            return
        }
        automaticConnectionQueue.append(endpoint)
        startAutomaticConnectionQueueIfNeeded()
    }

    private func startAutomaticConnectionQueueIfNeeded() {
        guard automaticConnectionEnabled,
              !isConnected,
              connectionTask == nil,
              !automaticConnectionQueue.isEmpty else {
            return
        }

        issue = nil
        let cycleID = automaticConnectionCycleID
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runAutomaticConnectionQueue(cycleID: cycleID)
        }
        connectionTask = task
    }

    private func runAutomaticConnectionQueue(cycleID: Int) async {
        while automaticConnectionEnabled,
              automaticConnectionCycleID == cycleID,
              !isConnected,
              !Task.isCancelled,
              !automaticConnectionQueue.isEmpty {
            let endpoint = automaticConnectionQueue.removeFirst()
            attemptedAutomaticEndpointIDs.insert(endpoint.id)
            connectionAttemptID += 1
            let attemptID = connectionAttemptID
            let connected = await performConnection(
                to: endpoint,
                attemptID: attemptID,
                presentsFailure: false
            )

            guard automaticConnectionEnabled,
                  automaticConnectionCycleID == cycleID,
                  !Task.isCancelled else {
                return
            }

            if connected {
                automaticConnectionEnabled = false
                automaticConnectionQueue = []
                lastAutomaticConnectionError = nil
                break
            }
        }

        guard automaticConnectionCycleID == cycleID else { return }
        connectionTask = nil
        finishAutomaticConnectionIfExhausted()
    }

    private func finishAutomaticConnectionIfExhausted() {
        guard automaticConnectionEnabled,
              !isConnected,
              !isDiscovering,
              connectionTask == nil,
              automaticConnectionQueue.isEmpty,
              let lastAutomaticConnectionError else {
            return
        }
        present(lastAutomaticConnectionError)
    }

    private func cancelAutomaticConnectionCycle() {
        automaticConnectionCycleID += 1
        automaticConnectionEnabled = false
        automaticConnectionQueue = []
        lastAutomaticConnectionError = nil
        connectionTask?.cancel()
        connectionTask = nil
    }

    private func markSuccessful(_ endpoint: FmoDeviceEndpoint) {
        lastSuccessfulEndpointID = endpoint.id
        endpoints.removeAll { $0.id == endpoint.id }
        endpoints.insert(endpoint, at: 0)
    }

    private func persistEndpointRegistry() async {
        await endpointStore.saveRegistry(
            FmoEndpointRegistry(
                endpoints: endpoints,
                lastSuccessfulEndpointID: lastSuccessfulEndpointID
            )
        )
    }

    @discardableResult
    private func refreshLocalStatus(from endpoint: FmoDeviceEndpoint) async -> Bool {
        dashboardSnapshot = await dashboardStore.beginLocalStatusConnection()

        do {
            try await localStatusProvider.connect(to: endpoint)
        } catch {
            dashboardSnapshot = await dashboardStore.recordLocalStatusDisconnection()
            return false
        }

        var update = DashboardLocalStatusUpdate()
        var hasCurrentServer = false

        if let value = try? await localStatusProvider.getCallsign() {
            update.callsign = value
        }
        if let value = try? await localStatusProvider.getCurrentServer() {
            update.currentServerName = value.name
            hasCurrentServer = true
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
        return hasCurrentServer
    }

    private func startLocalStatusRefresh(
        from endpoint: FmoDeviceEndpoint,
        requiresFullSnapshot: Bool
    ) {
        localStatusTask?.cancel()
        let waiter = statusRefreshWaiter
        let interval = currentServerRefreshInterval
        localStatusTask = Task { [weak self] in
            var needsFullSnapshot = requiresFullSnapshot

            while !Task.isCancelled {
                do {
                    try await waiter.wait(for: interval)
                } catch {
                    return
                }
                guard let self else { return }
                guard !Task.isCancelled,
                      selectedEndpoint?.id == endpoint.id,
                      isConnected else { return }

                if needsFullSnapshot {
                    needsFullSnapshot = !(await refreshLocalStatus(from: endpoint))
                    continue
                }

                do {
                    try await localStatusProvider.connect(to: endpoint)
                    let server = try await localStatusProvider.getCurrentServer()
                    guard !Task.isCancelled, selectedEndpoint?.id == endpoint.id else { return }
                    dashboardSnapshot = await dashboardStore.recordCurrentServer(server.name)
                } catch {
                    guard !Task.isCancelled, selectedEndpoint?.id == endpoint.id else { return }
                    dashboardSnapshot = await dashboardStore.recordLocalStatusDisconnection()
                    needsFullSnapshot = true
                }
            }
        }
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
        localStatusTask?.cancel()
        localStatusTask = nil
        localEventTask?.cancel()
        localEventTask = nil
        await localEventStream.disconnect()
        await localStatusProvider.disconnect()
    }

    @discardableResult
    private func merge(_ endpoint: FmoDeviceEndpoint) -> (endpoint: FmoDeviceEndpoint, inserted: Bool) {
        if let existingEndpoint = endpoints.first(where: { $0.id == endpoint.id }) {
            return (existingEndpoint, false)
        }
        endpoints.append(endpoint)
        return (endpoint, true)
    }
}
