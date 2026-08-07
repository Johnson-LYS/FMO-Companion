import Foundation

enum AppComposition {
    @MainActor
    struct Models {
        let device: DeviceHomeModel
        let locationAutomation: LocationAutomationModel
        let officialWeb: OfficialWebModel
        let fmoNetwork: FmoNetworkModel
        let fmoNetworkLocationProvider: any PhoneLocationProviding
    }

    @MainActor
    static func makeModels(processInfo: ProcessInfo = .processInfo) -> Models {
        let endpointStore: any FmoEndpointStoring
        let discovery: any FmoDeviceDiscovering
        let geoClient: any FmoGeoClient
        let localStatusProvider: any FmoLocalStatusProviding
        let localEventStream: any FmoLocalEventStreaming
        let modeStore: any LocationSyncModeStoring
        let aprsIdentityStore: any ReceiveOnlyAPRSIdentityStoring
        let aprsReceiver: any APRSISReceiving
        let aprsNetworkProcessor: any FMOV4NetworkProcessing
        let fmoNetworkLocationProvider: any PhoneLocationProviding

#if DEBUG
        switch processInfo.environment["FMO_UI_TEST_SCENARIO"] {
        case "local-network-denied":
            endpointStore = UserDefaultsFmoEndpointStore()
            discovery = LocalNetworkDeniedDiscovery()
            geoClient = FmoGeoWebSocketClient()
            localStatusProvider = FmoLocalStatusWebSocketClient()
            localEventStream = FmoLocalEventWebSocketClient()
        case "saved-device":
            let endpoint = try? FmoDeviceEndpoint(host: "fmo.local", source: .manual)
            endpointStore = UITestEndpointStore(endpoint: endpoint)
            discovery = EmptyDeviceDiscovery()
            geoClient = UITestGeoClient()
            localStatusProvider = UITestLocalStatusProvider()
            localEventStream = UITestLocalEventStream()
        case "dashboard-connected":
            let endpoint = try? FmoDeviceEndpoint(host: "fmo.local", source: .manual)
            endpointStore = UITestEndpointStore(endpoint: endpoint)
            discovery = EmptyDeviceDiscovery()
            geoClient = UITestGeoClient()
            localStatusProvider = UITestLocalStatusProvider()
            localEventStream = UITestLocalEventStream()
        case "automatic-connection":
            let savedEndpoint = try? FmoDeviceEndpoint(host: "fmo.local", source: .manual)
            let nearbyEndpoint = try? FmoDeviceEndpoint(host: "fmo-nearby.local", source: .bonjour, name: "FMO Nearby")
            endpointStore = UITestEndpointStore(endpoint: savedEndpoint)
            discovery = nearbyEndpoint.map(UITestSingleDeviceDiscovery.init(endpoint:)) ?? EmptyDeviceDiscovery()
            geoClient = UITestGeoClient()
            localStatusProvider = UITestLocalStatusProvider()
            localEventStream = UITestLocalEventStream()
        case "empty":
            endpointStore = UITestEndpointStore(endpoint: nil)
            discovery = EmptyDeviceDiscovery()
            geoClient = FmoGeoWebSocketClient()
            localStatusProvider = FmoLocalStatusWebSocketClient()
            localEventStream = FmoLocalEventWebSocketClient()
        default:
            endpointStore = UserDefaultsFmoEndpointStore()
            discovery = NWBrowserFmoDeviceDiscovery()
            geoClient = FmoGeoWebSocketClient()
            localStatusProvider = FmoLocalStatusWebSocketClient()
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
        } else {
            aprsIdentityStore = UserDefaultsReceiveOnlyAPRSIdentityStore()
            aprsReceiver = makeLiveAPRSReceiver()
            aprsNetworkProcessor = makeLiveAPRSNetworkProcessor()
            fmoNetworkLocationProvider = CoreLocationProvider()
        }
#else
        endpointStore = UserDefaultsFmoEndpointStore()
        discovery = NWBrowserFmoDeviceDiscovery()
        geoClient = FmoGeoWebSocketClient()
        localStatusProvider = FmoLocalStatusWebSocketClient()
        localEventStream = FmoLocalEventWebSocketClient()
        modeStore = UserDefaultsLocationSyncModeStore()
        aprsIdentityStore = UserDefaultsReceiveOnlyAPRSIdentityStore()
        aprsReceiver = makeLiveAPRSReceiver()
        aprsNetworkProcessor = makeLiveAPRSNetworkProcessor()
        fmoNetworkLocationProvider = CoreLocationProvider()
#endif

        let device = DeviceHomeModel(
            discovery: discovery,
            geoClient: geoClient,
            localStatusProvider: localStatusProvider,
            localEventStream: localEventStream,
            locationProvider: CoreLocationProvider(),
            endpointStore: endpointStore
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

        return Models(
            device: device,
            locationAutomation: locationAutomation,
            officialWeb: OfficialWebModel(),
            fmoNetwork: fmoNetwork,
            fmoNetworkLocationProvider: fmoNetworkLocationProvider
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
    private var endpoint: FmoDeviceEndpoint?

    init(endpoint: FmoDeviceEndpoint?) {
        self.endpoint = endpoint
    }

    func load() -> FmoDeviceEndpoint? { endpoint }
    func save(_ endpoint: FmoDeviceEndpoint?) { self.endpoint = endpoint }
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

private actor UITestLocalStatusProvider: FmoLocalStatusProviding {
    func connect(to endpoint: FmoDeviceEndpoint) {}
    func getCallsign() -> String { "BG0TST" }
    func getCurrentServer() -> FmoCurrentServer { FmoCurrentServer(uid: 42, name: "测试服务器") }
    func getServerFilter() -> FmoServerFilter { .kilometers(500) }
    func getWorkingFrequencyMHz() -> Double { 438.5 }
    func getQSOLogCount() -> Int { 18 }
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

#endif
