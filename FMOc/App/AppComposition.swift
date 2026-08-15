import Foundation

enum AppComposition {
    @MainActor
    struct Models {
        let device: DeviceHomeModel
        let locationAutomation: LocationAutomationModel
        let officialWeb: OfficialWebModel
        let fmoNetwork: FmoNetworkModel
        let aprsMessages: APRSMessageModel
        let remoteControl: FmoRemoteControlModel
        let qso: QSOModel
        let audioClient: any FmoLocalAudioStreaming
        let fmoNetworkLocationProvider: any PhoneLocationProviding
        let dashboardSpeakerLocationStore: any DashboardSpeakerLocationStoring
        let dashboardAreaResolver: any DashboardAreaResolving
    }

    @MainActor
    static func makeModels(processInfo: ProcessInfo = .processInfo) -> Models {
        let endpointStore: any FmoEndpointStoring
        let discovery: any FmoDeviceDiscovering
        let geoClient: any FmoGeoClient
        let localStatusProvider: any FmoLocalStatusProviding
        let stationController: any FmoStationControlling
        let localEventStream: any FmoLocalEventStreaming
        let modeStore: any LocationSyncModeStoring
        let aprsIdentityStore: any ReceiveOnlyAPRSIdentityStoring
        let aprsReceiver: any APRSISReceiving
        let aprsNetworkProcessor: any FMOV4NetworkProcessing
        let messagingClient: any APRSISMessaging
        let qsoReader: any FmoQSOReading
        let audioClient: any FmoLocalAudioStreaming
        let fmoNetworkLocationProvider: any PhoneLocationProviding

#if DEBUG
        switch processInfo.environment["FMO_UI_TEST_SCENARIO"] {
        case "local-network-denied":
            endpointStore = UserDefaultsFmoEndpointStore()
            discovery = LocalNetworkDeniedDiscovery()
            geoClient = FmoGeoWebSocketClient()
            localStatusProvider = FmoLocalStatusWebSocketClient()
            stationController = FmoStationControlWebSocketClient()
            localEventStream = FmoLocalEventWebSocketClient()
        case "saved-device":
            let endpoint = try? FmoDeviceEndpoint(host: "fmo.local", source: .manual)
            let serverState = UITestServerState()
            endpointStore = UITestEndpointStore(endpoint: endpoint)
            discovery = EmptyDeviceDiscovery()
            geoClient = UITestGeoClient()
            localStatusProvider = UITestLocalStatusProvider(serverState: serverState)
            stationController = UITestStationController(serverState: serverState)
            localEventStream = UITestLocalEventStream()
        case "dashboard-connected":
            let endpoint = try? FmoDeviceEndpoint(host: "fmo.local", source: .manual)
            let serverState = UITestServerState()
            endpointStore = UITestEndpointStore(endpoint: endpoint)
            discovery = EmptyDeviceDiscovery()
            geoClient = UITestGeoClient()
            localStatusProvider = UITestLocalStatusProvider(serverState: serverState)
            stationController = UITestStationController(
                serverState: serverState,
                catalogDelay: processInfo.environment["FMO_UI_TEST_DELAY_SERVER_CATALOG"] == "1"
                    ? .seconds(3)
                    : .zero
            )
            localEventStream = UITestLocalEventStream()
        case "qso-synced":
            let endpoint = try? FmoDeviceEndpoint(host: "fmo.local", source: .manual, name: "FMO Test")
            let serverState = UITestServerState()
            endpointStore = UITestEndpointStore(endpoint: endpoint)
            discovery = EmptyDeviceDiscovery()
            geoClient = UITestGeoClient()
            localStatusProvider = UITestLocalStatusProvider(serverState: serverState)
            stationController = UITestStationController(serverState: serverState)
            localEventStream = UITestLocalEventStream()
        case "automatic-connection":
            let savedEndpoint = try? FmoDeviceEndpoint(host: "fmo.local", source: .manual)
            let serverState = UITestServerState()
            let nearbyEndpoint = try? FmoDeviceEndpoint(
                host: FmoDeviceEndpoint.bonjourHost,
                port: 81,
                source: .bonjour,
                name: "FMO Nearby"
            )
            endpointStore = UITestEndpointStore(endpoint: savedEndpoint)
            discovery = nearbyEndpoint.map(UITestSingleDeviceDiscovery.init(endpoint:)) ?? EmptyDeviceDiscovery()
            geoClient = UITestGeoClient()
            localStatusProvider = UITestLocalStatusProvider(serverState: serverState)
            stationController = UITestStationController(serverState: serverState)
            localEventStream = UITestLocalEventStream()
        case "empty":
            endpointStore = UITestEndpointStore(endpoint: nil)
            discovery = EmptyDeviceDiscovery()
            geoClient = FmoGeoWebSocketClient()
            localStatusProvider = FmoLocalStatusWebSocketClient()
            stationController = FmoStationControlWebSocketClient()
            localEventStream = FmoLocalEventWebSocketClient()
        default:
            endpointStore = UserDefaultsFmoEndpointStore()
            discovery = NWBrowserFmoDeviceDiscovery()
            geoClient = FmoGeoWebSocketClient()
            localStatusProvider = FmoLocalStatusWebSocketClient()
            stationController = FmoStationControlWebSocketClient()
            localEventStream = FmoLocalEventWebSocketClient()
        }
        modeStore = processInfo.environment["FMO_UI_TEST_SCENARIO"] == nil
            ? UserDefaultsLocationSyncModeStore()
            : UITestLocationSyncModeStore()

        if let scenario = processInfo.environment["FMO_UI_TEST_SCENARIO"] {
            let identity = ["aprs-receiving", "aprs-network-content"].contains(scenario)
                ? try? ReceiveOnlyAPRSIdentity(callsign: "BG0TST", ssid: 10)
                : nil
            aprsIdentityStore = UITestAPRSIdentityStore(identity: identity)
            aprsReceiver = UITestAPRSReceiver()
            aprsNetworkProcessor = DiscardingFMOV4NetworkProcessor()
            fmoNetworkLocationProvider = UITestPhoneLocationProvider()
            audioClient = UnavailableFmoLocalAudioStream()
        } else {
            aprsIdentityStore = UserDefaultsReceiveOnlyAPRSIdentityStore()
            aprsReceiver = makeLiveAPRSReceiver()
            aprsNetworkProcessor = makeLiveAPRSNetworkProcessor()
            fmoNetworkLocationProvider = CoreLocationProvider()
            audioClient = FmoLocalAudioClient()
        }
#else
        endpointStore = UserDefaultsFmoEndpointStore()
        discovery = NWBrowserFmoDeviceDiscovery()
        geoClient = FmoGeoWebSocketClient()
        localStatusProvider = FmoLocalStatusWebSocketClient()
        stationController = FmoStationControlWebSocketClient()
        localEventStream = FmoLocalEventWebSocketClient()
        modeStore = UserDefaultsLocationSyncModeStore()
        aprsIdentityStore = UserDefaultsReceiveOnlyAPRSIdentityStore()
        aprsReceiver = makeLiveAPRSReceiver()
        aprsNetworkProcessor = makeLiveAPRSNetworkProcessor()
        fmoNetworkLocationProvider = CoreLocationProvider()
        audioClient = FmoLocalAudioClient()
#endif

        let dashboardSpeakerLocationStore: any DashboardSpeakerLocationStoring =
            processInfo.environment["FMO_UI_TEST_SCENARIO"] == nil
            ? UserDefaultsDashboardSpeakerLocationStore()
            : VolatileDashboardSpeakerLocationStore()
        let dashboardAreaResolver: any DashboardAreaResolving
#if DEBUG
        dashboardAreaResolver = processInfo.environment["FMO_UI_TEST_SCENARIO"] == nil
            ? MapKitDashboardAreaResolver()
            : UITestDashboardAreaResolver()
#else
        dashboardAreaResolver = MapKitDashboardAreaResolver()
#endif
        let device = DeviceHomeModel(
            discovery: discovery,
            geoClient: geoClient,
            localStatusProvider: localStatusProvider,
            stationController: stationController,
            localEventStream: localEventStream,
            locationProvider: CoreLocationProvider(),
            endpointStore: endpointStore,
            dashboardStore: DashboardStore(
                speakerLocationStore: dashboardSpeakerLocationStore
            )
        )
        let coordinator = AutomaticLocationSyncCoordinator(
            locationProvider: CoreLocationAutomaticProvider(),
            networkObserver: NWPathNetworkObserver(),
            geoClient: FmoGeoWebSocketClient(),
            endpointStore: endpointStore,
            modeStore: modeStore
        )
        let locationAutomation = LocationAutomationModel(
            coordinator: coordinator,
            authorizationReader: CoreLocationAuthorizationReader()
        )
        let fmoNetwork = FmoNetworkModel(
            receiver: aprsReceiver,
            identityStore: aprsIdentityStore,
            networkProcessor: aprsNetworkProcessor,
            initialSnapshot: makeInitialAPRSNetworkSnapshot(processInfo: processInfo)
        )
        let messagingProtocol: APRSISMessagingProtocol
        do {
            let version = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0.6"
            messagingProtocol = try APRSISMessagingProtocol(
                softwareName: "FMOCompanion",
                softwareVersion: version
            )
        } catch {
            preconditionFailure("Invalid static APRS-IS messaging identity")
        }
#if DEBUG
        if processInfo.environment["FMO_UI_TEST_SCENARIO"] == "qso-synced" {
            messagingClient = UITestAPRSMessagingClient()
            qsoReader = UITestQSOReader()
        } else if processInfo.environment["FMO_UI_TEST_SCENARIO"] != nil {
            messagingClient = UITestAPRSMessagingClient()
            qsoReader = UnavailableFmoQSOReader()
        } else {
            messagingClient = APRSISMessagingClient(messagingProtocol: messagingProtocol)
            qsoReader = FmoQSOReadClient()
        }
#else
        messagingClient = APRSISMessagingClient(messagingProtocol: messagingProtocol)
        qsoReader = FmoQSOReadClient()
#endif
        let aprsMessages = APRSMessageModel(client: messagingClient)
        let remoteControl = FmoRemoteControlModel(client: messagingClient)
        let qso = QSOModel(reader: qsoReader)
        aprsMessages.controlMessageHandler = { [weak remoteControl] envelope in
            remoteControl?.handleControlMessage(envelope) ?? false
        }

        return Models(
            device: device,
            locationAutomation: locationAutomation,
            officialWeb: OfficialWebModel(),
            fmoNetwork: fmoNetwork,
            aprsMessages: aprsMessages,
            remoteControl: remoteControl,
            qso: qso,
            audioClient: audioClient,
            fmoNetworkLocationProvider: fmoNetworkLocationProvider,
            dashboardSpeakerLocationStore: dashboardSpeakerLocationStore,
            dashboardAreaResolver: dashboardAreaResolver
        )
    }

    @MainActor
    static func makeDeviceModel(processInfo: ProcessInfo = .processInfo) -> DeviceHomeModel {
        makeModels(processInfo: processInfo).device
    }

    private static func makeLiveAPRSReceiver() -> any APRSISReceiving {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.4"
        guard let aprsISProtocol = try? APRSISProtocol(
            softwareName: "FMOCompanion",
            softwareVersion: version
        ) else {
            preconditionFailure("Invalid static APRS-IS software identity")
        }
        return APRSISReceiveOnlyClient(aprsISProtocol: aprsISProtocol)
    }

    private static func makeLiveAPRSNetworkProcessor() -> any FMOV4NetworkProcessing {
        let verifier = FMOV4Verifier(
            trustMaterial: .official,
            revocationChecker: OfficialFMOV4CRLStore()
        )
        return FMOV4NetworkStore(verifier: verifier)
    }

    private static func makeInitialAPRSNetworkSnapshot(
        processInfo: ProcessInfo
    ) -> FMOV4NetworkSnapshot {
#if DEBUG
        guard processInfo.environment["FMO_UI_TEST_SCENARIO"] == "aprs-network-content" else {
            return .empty
        }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let rootCRL = FMOV4CRLFreshness.notPublished
        let intermediateCRL = FMOV4CRLFreshness.current(
            number: 5,
            nextUpdate: date.addingTimeInterval(86_400)
        )
        let station = FMOV4StationRecord(
            id: "BG0AAA-10",
            callsign: "BG0AAA",
            ssid: 10,
            latitude: 31.2304,
            longitude: 121.4737,
            serverUID: 123,
            frequency: "438.5000",
            lastActivity: .cq,
            observedAt: date,
            certificateExpiresAt: date.addingTimeInterval(365 * 86_400),
            issuerSerialNumber: 1_001,
            trustLevel: .trusted,
            rootCRL: rootCRL,
            intermediateCRL: intermediateCRL
        )
        let server = FMOV4ServerRecord(
            uid: 123,
            name: "华东测试服务器",
            countryCode: "CN",
            host: "fmo.example.invalid",
            port: 1_883,
            filterKilometers: 500,
            onlineUserCount: 24,
            peakUserCount: 37,
            latitude: station.latitude,
            longitude: station.longitude,
            broadcasterCallsign: station.id,
            observedAt: date,
            trustLevel: .trusted
        )
        let event = FMOV4NetworkEvent(
            id: "ui-test-cq",
            kind: .cq,
            callsign: station.callsign,
            ssid: station.ssid,
            latitude: station.latitude,
            longitude: station.longitude,
            serverUID: server.uid,
            topic: nil,
            content: nil,
            observedAt: date,
            trustLevel: .trusted
        )
        return FMOV4NetworkSnapshot(stations: [station], servers: [server], events: [event])
#else
        return .empty
#endif
    }
}

#if DEBUG
private nonisolated struct LocalNetworkDeniedDiscovery: FmoDeviceDiscovering {
    func discover(timeout: Duration) -> AsyncThrowingStream<FmoDeviceEndpoint, any Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: FmoDeviceError.localNetworkDenied)
        }
    }
}

private nonisolated struct EmptyDeviceDiscovery: FmoDeviceDiscovering {
    func discover(timeout: Duration) -> AsyncThrowingStream<FmoDeviceEndpoint, any Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private nonisolated struct UITestPhoneLocationProvider: PhoneLocationProviding {
    func currentLocation() throws -> PhoneLocationSample {
        PhoneLocationSample(
            coordinate: try GeoCoordinate(latitude: 31.2304, longitude: 121.4737),
            horizontalAccuracy: 5,
            isAccuracyLimited: false
        )
    }
}

private nonisolated struct UITestSingleDeviceDiscovery: FmoDeviceDiscovering {
    let endpoint: FmoDeviceEndpoint

    func discover(timeout: Duration) -> AsyncThrowingStream<FmoDeviceEndpoint, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(endpoint)
            continuation.finish()
        }
    }
}

private actor UITestEndpointStore: FmoEndpointStoring {
    private var registry: FmoEndpointRegistry

    init(endpoint: FmoDeviceEndpoint?) {
        registry = FmoEndpointRegistry(
            endpoints: endpoint.map { [$0] } ?? [],
            lastSuccessfulEndpointID: endpoint?.id
        )
    }

    func loadRegistry() -> FmoEndpointRegistry { registry }
    func saveRegistry(_ registry: FmoEndpointRegistry) { self.registry = registry }
}

private actor UITestLocationSyncModeStore: LocationSyncModeStoring {
    private var mode = LocationSyncMode.manual

    func load() -> LocationSyncMode { mode }
    func save(_ mode: LocationSyncMode) { self.mode = mode }
}

private actor UITestAPRSIdentityStore: ReceiveOnlyAPRSIdentityStoring {
    private var configuration: ReceiveOnlyAPRSIdentityConfiguration?

    init(identity: ReceiveOnlyAPRSIdentity?) {
        configuration = identity.map {
            ReceiveOnlyAPRSIdentityConfiguration(identity: $0, source: .manual)
        }
    }

    func load() -> ReceiveOnlyAPRSIdentityConfiguration? { configuration }

    func saveManual(_ identity: ReceiveOnlyAPRSIdentity) {
        configuration = ReceiveOnlyAPRSIdentityConfiguration(
            identity: identity,
            source: .manual
        )
    }

    func adoptInherited(_ identity: ReceiveOnlyAPRSIdentity) {
        guard configuration?.source != .manual else { return }
        configuration = ReceiveOnlyAPRSIdentityConfiguration(
            identity: identity,
            source: .inherited
        )
    }
}

private actor UITestAPRSMessagingClient: APRSISMessaging {
    func events(
        identity _: ReceiveOnlyAPRSIdentity,
        endpoint _: APRSISEndpoint
    ) -> AsyncThrowingStream<APRSISMessagingEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.sessionReady(serverCallsign: "T2UITEST"))
        }
    }

    func send(packet _: String) {}
    func disconnect() {}
}

private actor UITestAPRSReceiver: APRSISReceiving {
    private var continuation: AsyncThrowingStream<APRSISInboundEvent, any Error>.Continuation?

    func events(
        identity: ReceiveOnlyAPRSIdentity,
        endpoint: APRSISEndpoint
    ) -> AsyncThrowingStream<APRSISInboundEvent, any Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            continuation.yield(.sessionReady(serverCallsign: "T2TEST"))
        }
    }

    func disconnect() {
        continuation?.finish()
        continuation = nil
    }
}

private actor UITestGeoClient: FmoGeoClient {
    func connect(to endpoint: FmoDeviceEndpoint) {}
    func getCoordinate() throws -> GeoCoordinate {
        try GeoCoordinate(latitude: 31.2304, longitude: 121.4737)
    }
    func setCoordinate(_ coordinate: GeoCoordinate) {}
    func disconnect() {}
}

private actor UITestQSOReader: FmoQSOReading {
    private var isConnected = false

    func connect(to endpoint: FmoDeviceEndpoint) { isConnected = true }

    func list(page: Int, pageSize: Int) throws -> FmoQSOListPage {
        guard isConnected else { throw FmoDeviceError.disconnected }
        let summaries = page == 0 ? details.map {
            FmoQSOSummary(
                logID: $0.logID,
                timestamp: $0.timestamp,
                toCallsign: $0.toCallsign,
                toGrid: $0.toGrid
            )
        } : []
        return FmoQSOListPage(totalCount: details.count, page: page, pageSize: pageSize, summaries: summaries)
    }

    func detail(logID: Int64) throws -> FmoQSODetail {
        guard isConnected, let detail = details.first(where: { $0.logID == logID }) else {
            throw FmoDeviceError.protocolViolation
        }
        return detail
    }

    func disconnect() { isConnected = false }

    private var details: [FmoQSODetail] {
        [
            FmoQSODetail(
                logID: 2,
                timestamp: Date(timeIntervalSince1970: 1_800_000_120),
                fromCallsign: "BG0OWN",
                toCallsign: "BH0TST",
                fromGrid: "OM89AA",
                toGrid: "PM01AB",
                frequencyRaw: 1_458_000,
                mode: "FM",
                relayName: "示例中继",
                relayAdmin: "BG0ADM",
                comment: "73"
            ),
            FmoQSODetail(
                logID: 1,
                timestamp: Date(timeIntervalSince1970: 1_800_000_000),
                fromCallsign: "BG0OWN",
                toCallsign: "BD0TST",
                fromGrid: "OM89AA",
                toGrid: "OL72AA",
                frequencyRaw: 1_458_000,
                mode: "FM",
                relayName: "示例中继",
                relayAdmin: nil,
                comment: nil
            ),
        ]
    }
}

private actor UITestServerState {
    private var current = FmoCurrentServer(uid: 42, name: "测试服务器")

    func currentServer() -> FmoCurrentServer { current }

    func select(_ server: FmoCurrentServer) {
        current = server
    }
}

private actor UITestLocalStatusProvider: FmoLocalStatusProviding {
    private let serverState: UITestServerState

    init(serverState: UITestServerState) {
        self.serverState = serverState
    }

    func connect(to endpoint: FmoDeviceEndpoint) {}
    func getCallsign() -> String { "BG0TST" }
    func getCurrentServer() async -> FmoCurrentServer { await serverState.currentServer() }
    func getServerFilter() -> FmoServerFilter { .kilometers(500) }
    func getWorkingFrequencyMHz() -> Double { 438.5 }
    func getQSOLogCount() -> Int { 18 }
    func disconnect() {}
}

private actor UITestStationController: FmoStationControlling {
    private let serverState: UITestServerState
    private let catalogDelay: Duration

    init(serverState: UITestServerState, catalogDelay: Duration = .zero) {
        self.serverState = serverState
        self.catalogDelay = catalogDelay
    }

    func connect(to endpoint: FmoDeviceEndpoint) {}

    func getServerCatalog() async throws -> FmoDeviceServerCatalog {
        if catalogDelay > .zero {
            try await Task.sleep(for: catalogDelay)
        }
        return FmoDeviceServerCatalog(
            all: [
                FmoDeviceServer(uid: 42, name: "测试服务器"),
                FmoDeviceServer(uid: 84, name: "备用服务器"),
            ],
            pinned: [FmoDeviceServer(uid: 84, name: "备用服务器")]
        )
    }

    func switchCurrentServer(toUID uid: Int64) async throws -> FmoCurrentServer {
        guard let server = try await getServerCatalog().all.first(where: { $0.uid == uid }) else {
            throw FmoDeviceError.protocolViolation
        }
        let current = FmoCurrentServer(uid: server.uid, name: server.name)
        await serverState.select(current)
        return current
    }

    func disconnect() {}
}

private nonisolated struct UITestLocalEventStream: FmoLocalEventStreaming {
    func events(from endpoint: FmoDeviceEndpoint) async -> AsyncThrowingStream<FmoLocalEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                .history([
                    FmoRecentLocalActivity(
                        callsign: "BG1ABC",
                        occurredAt: Date(timeIntervalSince1970: 1_700_000_000)
                    )
                ])
            )
            continuation.yield(
                .speaking(
                    FmoSpeakingState(
                        callsign: "BG1ABC",
                        grid: "OM20xx",
                        isSpeaking: true,
                        sequence: 1,
                        deviceUptimeMilliseconds: 10
                    )
                )
            )
        }
    }

    func disconnect() {}
}

@MainActor
private struct UITestDashboardAreaResolver: DashboardAreaResolving {
    func areaName(for coordinate: GeoCoordinate) async -> String? {
        "四川省南充市"
    }
}

#endif
