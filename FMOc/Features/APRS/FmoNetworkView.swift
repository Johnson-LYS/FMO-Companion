import MapKit
import SwiftData
import SwiftUI

struct FmoNetworkView: View {
    @Bindable var model: FmoNetworkModel
    @Bindable var messageModel: APRSMessageModel
    @State private var mapModel: FmoNetworkMapModel
    @State private var isPresentingIdentity = false
    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.5, longitude: 108.5),
            span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)
        )
    )
    @State private var eventFilter = NetworkHomeEventFilter.all
    @Query private var favoriteCallsigns: [FavoriteCallsign]
    @Query private var favoriteServers: [FavoriteServer]

    init(
        model: FmoNetworkModel,
        messageModel: APRSMessageModel,
        locationProvider: any PhoneLocationProviding = CoreLocationProvider()
    ) {
        self.model = model
        self.messageModel = messageModel
        _mapModel = State(
            initialValue: FmoNetworkMapModel(locationProvider: locationProvider)
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.sectionSpacing) {
                if let identity = model.identity {
                    identityBar(identity)
                    networkContent
                } else {
                    setupCard
                }
            }
            .padding(AppTheme.pageSpacing)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("FMO 网络")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if model.identity != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    distanceScopeMenu
                }
            }
        }
        .task {
            await model.setActive(true)
            await messageModel.setActive(true)
        }
        .task(id: model.identity != nil) {
            guard model.identity != nil else { return }
            guard let coordinate = await mapModel.prepareDefaultDistanceScope() else { return }
            guard let kilometers = mapModel.distanceScope.kilometers else { return }
            centerMap(
                on: coordinate,
                latitudeDelta: max(0.08, min(60, kilometers / 55))
            )
        }
        .sheet(isPresented: $isPresentingIdentity) {
            FmoNetworkIdentitySheet(
                identity: model.identity,
                save: model.saveManualIdentity
            )
        }
        .alert(
            "无法获取位置",
            isPresented: Binding(
                get: { mapModel.locationErrorMessage != nil },
                set: { if !$0 { mapModel.dismissLocationError() } }
            )
        ) {
            Button("好") { mapModel.dismissLocationError() }
        } message: {
            Text(mapModel.locationErrorMessage ?? String(localized: "暂时无法获取当前位置"))
        }
    }

    private var setupCard: some View {
        Button {
            isPresentingIdentity = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 4) {
                    Text("设置网络身份")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("填写呼号后即可接收 FMO 网络动态")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .fullWidthRowHitArea()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: .rect(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(uiColor: .separator).opacity(0.28), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("aprs-identity-setup")
    }

    private func identityBar(_ identity: ReceiveOnlyAPRSIdentity) -> some View {
        Button {
            isPresentingIdentity = true
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)

                Text(identity.loginCallsign)
                    .font(.headline.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if model.phase == .connecting {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(model.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .fullWidthRowHitArea()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: .rect(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(uiColor: .separator).opacity(0.28), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("aprs-session-bar")
        .accessibilityValue("\(identity.loginCallsign)，\(model.statusText)")
    }

    @ViewBuilder
    private var networkContent: some View {
        VStack(spacing: AppTheme.sectionSpacing) {
            mapCard
            eventFilters
            recentEvents
            explorationLinks
        }
    }

    private var mapCard: some View {
        networkMap
        .accessibilityIdentifier("aprs-network-map")
        .frame(height: 252)
        .clipShape(.rect(cornerRadius: AppTheme.cardRadius))
        .overlay(alignment: .topTrailing) {
            Label(
                "\(scopedSnapshot.stations.count) 个台站",
                systemImage: "mappin.and.ellipse"
            )
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(.primary)
            .background(.ultraThickMaterial, in: .capsule)
            .padding(12)
        }
        .overlay(alignment: .topLeading) {
            if scopedSnapshot.stations.isEmpty {
                Label(emptyMapText, systemImage: contentSymbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.ultraThickMaterial, in: .capsule)
                    .padding(12)
            }
        }
        .overlay(alignment: .bottomLeading) {
            trackingControl
                .padding(12)
        }
        .overlay(alignment: .bottomTrailing) {
            locationControl
                .padding(12)
        }
        .onChange(of: scopedSnapshot.stations) { _, stations in
            guard mapModel.isAutoTrackingEnabled else { return }
            guard let first = stations.first else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                mapPosition = .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(
                            latitude: first.latitude,
                            longitude: first.longitude
                        ),
                        span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
                    )
                )
            }
        }
    }

    private var trackingControl: some View {
        HStack(spacing: 7) {
            Image(systemName: "scope")
                .font(.caption.weight(.semibold))
            Text("追踪")
                .font(.caption.weight(.semibold))
            Toggle(
                "自动追踪",
                isOn: Binding(
                    get: { mapModel.isAutoTrackingEnabled },
                    set: { mapModel.isAutoTrackingEnabled = $0 }
                )
            )
            .labelsHidden()
            .controlSize(.mini)
            .accessibilityIdentifier("aprs-map-auto-tracking")
        }
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .frame(minHeight: 40)
        .background(.ultraThickMaterial, in: .capsule)
    }

    private var locationControl: some View {
        Button {
            Task {
                guard let coordinate = await mapModel.locate() else { return }
                centerMap(on: coordinate, latitudeDelta: 0.08)
            }
        } label: {
            if mapModel.isLocating {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "location.fill")
                    .font(.body.weight(.semibold))
            }
        }
        .frame(width: 44, height: 44)
        .foregroundStyle(Color.accentColor)
        .background(.ultraThickMaterial, in: .circle)
        .buttonStyle(.plain)
        .disabled(mapModel.isLocating)
        .accessibilityLabel("我的位置")
        .accessibilityIdentifier("aprs-map-my-location")
    }

    private var distanceScopeMenu: some View {
        Menu {
            ForEach(FmoNetworkDistanceScope.allCases) { scope in
                Button {
                    Task { await selectDistanceScope(scope) }
                } label: {
                    if mapModel.distanceScope == scope {
                        Label(scope.title, systemImage: "checkmark")
                    } else {
                        Text(scope.title)
                    }
                }
            }
        } label: {
            Text(mapModel.distanceScope.title)
                .monospacedDigit()
        }
        .accessibilityLabel("范围过滤")
        .accessibilityValue(mapModel.distanceScope.accessibilityTitle)
        .accessibilityIdentifier("aprs-distance-scope-menu")
    }

    @ViewBuilder
    private var networkMap: some View {
#if DEBUG
        if ProcessInfo.processInfo.environment["FMO_UI_TEST_SCENARIO"] == "aprs-network-content" {
            ZStack {
                Color(uiColor: .secondarySystemGroupedBackground)
                Image(systemName: "map")
                    .font(.system(size: 80, weight: .ultraLight))
                    .foregroundStyle(.tertiary)
                ForEach(Array(scopedSnapshot.stations.enumerated()), id: \.element.id) { index, station in
                    Label(station.id, systemImage: "mappin.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                        .offset(x: CGFloat(index * 34 - 18), y: CGFloat(index * 28 - 6))
                }
            }
        } else {
            liveMap
        }
#else
        liveMap
#endif
    }

    private var liveMap: some View {
        Map(position: $mapPosition) {
            ForEach(scopedSnapshot.stations) { station in
                Marker(
                    station.id,
                    coordinate: CLLocationCoordinate2D(
                        latitude: station.latitude,
                        longitude: station.longitude
                    )
                )
                .tint(Color.accentColor)
            }
            if let coordinate = mapModel.ownCoordinate {
                Annotation(
                    "我的位置",
                    coordinate: CLLocationCoordinate2D(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )
                ) {
                    ZStack {
                        Circle()
                            .fill(.blue.opacity(0.18))
                            .frame(width: 26, height: 26)
                        Circle()
                            .fill(.blue)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .accessibilityLabel("我的位置")
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }

    private var eventFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(NetworkHomeEventFilter.allCases) { filter in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { eventFilter = filter }
                    } label: {
                        Label(filter.title, systemImage: filter.symbol)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 13)
                            .frame(minHeight: 36)
                            .foregroundStyle(eventFilter == filter ? .black : .primary)
                            .background(
                                eventFilter == filter ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground),
                                in: .capsule
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var recentEvents: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近动态")
                    .font(.headline)
                Label("24h · 200", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("保留最近 24 小时，最多 200 条")
                Spacer()
                NavigationLink("查看全部") {
                    FMOV4EventExplorerView(snapshot: scopedSnapshot)
                }
                .font(.subheadline)
            }

            if filteredEvents.isEmpty {
                ContentUnavailableView(
                    eventFilter.emptyTitle,
                    systemImage: eventFilter.symbol,
                    description: Text(eventFilter.emptyDescription)
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredEvents.prefix(3))) { event in
                        FMOV4EventRow(event: event)
                        if event.id != filteredEvents.prefix(3).last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(.background.secondary, in: .rect(cornerRadius: 18))
            }
        }
    }

    private var explorationLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("继续探索")
                .font(.headline)

            VStack(spacing: 0) {
                NavigationLink {
                    FMOV4StationDirectoryView(snapshot: scopedSnapshot)
                } label: {
                    explorationRow(
                        title: "台站与服务器",
                        subtitle: "搜索、收藏与详细信息",
                        symbol: "location.magnifyingglass"
                    )
                }
                .accessibilityIdentifier("aprs-station-directory-entry")
                Divider().padding(.leading, 60)
                NavigationLink {
                    FMOV4EventExplorerView(snapshot: scopedSnapshot)
                } label: {
                    explorationRow(
                        title: "完整事件流",
                        subtitle: "CQ、语音、上线与服务广播",
                        symbol: "waveform.path.ecg"
                    )
                }
                .accessibilityIdentifier("aprs-event-explorer-entry")
                Divider().padding(.leading, 60)
                NavigationLink {
                    APRSMessagesView(model: messageModel)
                } label: {
                    explorationRow(
                        title: "APRS 消息",
                        subtitle: "发送消息并跟踪确认状态",
                        symbol: "message"
                    )
                }
                .accessibilityIdentifier("aprs-messages-entry")
            }
            .buttonStyle(.plain)
            .background(.background.secondary, in: .rect(cornerRadius: 18))
        }
    }

    private func explorationRow(title: LocalizedStringKey, subtitle: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .fullWidthRowHitArea()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var filteredEvents: [FMOV4NetworkEvent] {
        let callsigns = Set(favoriteCallsigns.map(\.normalizedCallsign))
        let serverUIDs = Set(favoriteServers.compactMap(\.numericUID))
        return scopedSnapshot.events.filter { event in
            switch eventFilter {
            case .all:
                true
            case .online:
                event.kind == .online
            case .calls:
                [.cq, .omcq, .vocal].contains(event.kind)
            case .favorites:
                callsigns.contains(FMOV4FavoriteKey.callsign(event.callsign))
                    || event.serverUID.map(serverUIDs.contains) == true
            }
        }
    }

    private var scopedSnapshot: FMOV4NetworkSnapshot {
        mapModel.visibleSnapshot(model.networkSnapshot)
    }

    private func selectDistanceScope(_ scope: FmoNetworkDistanceScope) async {
        guard let coordinate = await mapModel.selectDistanceScope(scope) else { return }
        guard let kilometers = scope.kilometers else { return }
        centerMap(
            on: coordinate,
            latitudeDelta: max(0.08, min(60, kilometers / 55))
        )
    }

    private func centerMap(on coordinate: GeoCoordinate, latitudeDelta: Double) {
        withAnimation(.easeInOut(duration: 0.35)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    ),
                    span: MKCoordinateSpan(
                        latitudeDelta: latitudeDelta,
                        longitudeDelta: latitudeDelta
                    )
                )
            )
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .receiving:
            .green
        case .connecting:
            .orange
        case .unconfigured, .paused, .waitingToRetry:
            .secondary
        }
    }

    private var contentSymbol: String {
        switch model.phase {
        case .receiving:
            "dot.radiowaves.left.and.right"
        case .connecting:
            "network"
        case .waitingToRetry:
            "wifi.exclamationmark"
        case .paused:
            "pause.circle"
        case .unconfigured:
            "person.crop.circle.badge.plus"
        }
    }

    private var emptyMapText: LocalizedStringKey {
        switch model.phase {
        case .receiving:
            "等待台站"
        case .connecting:
            "正在连接"
        case .waitingToRetry:
            "等待网络恢复"
        case .paused:
            "接收已暂停"
        case .unconfigured:
            "设置网络身份"
        }
    }
}

private extension FmoNetworkDistanceScope {
    var title: String {
        self == .all ? String(localized: "全网") : "\(rawValue) km"
    }

    var accessibilityTitle: String {
        self == .all
            ? String(localized: "全网")
            : String(localized: "当前位置 \(rawValue) 公里内")
    }
}

private enum NetworkHomeEventFilter: String, CaseIterable, Identifiable {
    case all
    case online
    case calls
    case favorites

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .all: "全部"
        case .online: "在线"
        case .calls: "呼叫"
        case .favorites: "收藏"
        }
    }

    var symbol: String {
        switch self {
        case .all: "line.3.horizontal.decrease"
        case .online: "dot.radiowaves.left.and.right"
        case .calls: "megaphone"
        case .favorites: "star"
        }
    }

    var emptyTitle: LocalizedStringKey {
        switch self {
        case .favorites: "收藏暂无动态"
        default: "暂无动态"
        }
    }

    var emptyDescription: LocalizedStringKey {
        switch self {
        case .favorites: "可先在台站与服务器目录中添加收藏。"
        default: "收到网络数据后会自动更新。"
        }
    }
}

private struct FmoNetworkIdentitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var callsign: String
    @State private var ssid: Int
    @State private var issue: FmoNetworkIdentityIssue?

    let save: @MainActor (String, Int) async -> FmoNetworkIdentityIssue?

    init(
        identity: ReceiveOnlyAPRSIdentity?,
        save: @escaping @MainActor (String, Int) async -> FmoNetworkIdentityIssue?
    ) {
        _callsign = State(initialValue: identity?.callsign ?? "")
        _ssid = State(initialValue: identity.map { Int($0.ssid) } ?? 10)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("呼号", text: $callsign)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("aprs-callsign-field")

                    Stepper(value: $ssid, in: 0 ... 15) {
                        LabeledContent("设备编号（SSID）", value: String(ssid))
                    }
                    .accessibilityIdentifier("aprs-ssid-stepper")
                } footer: {
                    Text("SSID 用于区分同一呼号下的不同设备。")
                }

                if let issue {
                    Section {
                        Label(issue.message, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("aprs-identity-error")
                    }
                }
            }
            .navigationTitle("网络身份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            issue = await save(callsign, ssid)
                            if issue == nil {
                                dismiss()
                            }
                        }
                    }
                    .accessibilityIdentifier("aprs-identity-save")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
