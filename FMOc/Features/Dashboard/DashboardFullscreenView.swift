import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct DashboardFullscreenView: View {
    private enum VisualMode: String, CaseIterable {
        case bearing
        case map

        var title: LocalizedStringResource { self == .bearing ? "方位" : "地图" }
        var symbol: String { self == .bearing ? "location.north.fill" : "map.fill" }
    }

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Bindable var audioMonitor: FmoAudioMonitorModel
    let dashboard: DashboardSnapshot
    let ownCoordinate: GeoCoordinate?
    let networkSnapshot: FMOV4NetworkSnapshot
    let deviceName: String
    let heroNamespace: Namespace.ID
    let showsExpandedContent: Bool
    let activatesExpandedServices: Bool
    let close: () -> Void
    private let areaResolver: any DashboardAreaResolving
    private let speakerLocationStore: any DashboardSpeakerLocationStoring
    @Binding var showsServerPicker: Bool

    @State private var visualMode = VisualMode.bearing
    @State private var areaName: String?
    @State private var historyAreaNames: [String: String] = [:]
    @State private var retainedAreaNames: [String: String] = [:]

    init(
        dashboard: DashboardSnapshot,
        ownCoordinate: GeoCoordinate?,
        networkSnapshot: FMOV4NetworkSnapshot,
        deviceName: String,
        audioMonitor: FmoAudioMonitorModel,
        areaResolver: any DashboardAreaResolving = MapKitDashboardAreaResolver(),
        speakerLocationStore: any DashboardSpeakerLocationStoring = VolatileDashboardSpeakerLocationStore(),
        heroNamespace: Namespace.ID,
        showsExpandedContent: Bool,
        activatesExpandedServices: Bool,
        showsServerPicker: Binding<Bool>,
        close: @escaping () -> Void
    ) {
        self.dashboard = dashboard
        self.ownCoordinate = ownCoordinate
        self.networkSnapshot = networkSnapshot
        self.deviceName = deviceName
        self.audioMonitor = audioMonitor
        self.areaResolver = areaResolver
        self.speakerLocationStore = speakerLocationStore
        self.heroNamespace = heroNamespace
        self.showsExpandedContent = showsExpandedContent
        self.activatesExpandedServices = activatesExpandedServices
        _showsServerPicker = showsServerPicker
        self.close = close
    }

    private var presentation: DashboardFullscreenPresentation {
        .make(
            dashboard: dashboard,
            ownCoordinate: ownCoordinate,
            network: networkSnapshot
        )
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                landscapeContent
            } else {
                portraitFallback
            }
        }
        .foregroundStyle(.white)
        .background {
            fullscreenBackground
                .ignoresSafeArea()
                .matchedGeometryEffect(
                    id: DashboardHeroElement.container,
                    in: heroNamespace,
                    properties: .frame,
                    anchor: .center,
                    isSource: false
                )
        }
        .task(id: "\(targetAreaResolutionID)-\(activatesExpandedServices)") {
            areaName = nil
            guard activatesExpandedServices else { return }
            guard let target = presentation.target,
                  let coordinate = target.coordinate else { return }
            let cached = await speakerLocationStore.location(for: target.callsign)
            if cached?.coordinate == coordinate, let cachedArea = cached?.areaName {
                areaName = cachedArea
                retainedAreaNames[historyKey(target.callsign)] = cachedArea
                return
            }
            let resolvedArea = await areaResolver.areaName(for: coordinate)
            guard !Task.isCancelled else { return }
            areaName = resolvedArea
            if let resolvedArea {
                retainedAreaNames[historyKey(target.callsign)] = resolvedArea
            }
            await speakerLocationStore.save(
                DashboardSpeakerLocation(
                    callsign: target.callsign,
                    coordinate: coordinate,
                    grid: target.grid,
                    areaName: resolvedArea,
                    updatedAt: .now
                )
            )
        }
        .task(id: "\(historyAreaResolutionID)-\(activatesExpandedServices)") {
            guard activatesExpandedServices else { return }
            await resolveHistoryAreaNames()
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
    }

    private var landscapeContent: some View {
        VStack(spacing: 10) {
            header
            if showsExpandedContent {
                HStack(spacing: 10) {
                    speakerPanel
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 310)
                    visualPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(expandedContentTransition)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var portraitFallback: some View {
        VStack(spacing: 10) {
            header

            if showsExpandedContent {
                ScrollView {
                    VStack(spacing: 10) {
                        speakerPanel.frame(minHeight: 300)
                        visualPanel.frame(height: 360)
                    }
                }
                .transition(expandedContentTransition)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                close()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.07), in: .rect(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("退出全屏仪表盘")
            .accessibilityIdentifier("dashboard-fullscreen-close")

            VStack(alignment: .leading, spacing: 4) {
                Text(dashboard.callsign.value ?? "FMO")
                    .font(.title.bold().monospaced())
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .matchedGeometryEffect(
                        id: DashboardHeroElement.callsign,
                        in: heroNamespace,
                        properties: .frame,
                        anchor: .leading,
                        isSource: false
                    )
                HStack(spacing: 7) {
                    if let grid = dashboard.maidenhead.value {
                        compactMetadata(grid, symbol: "location.fill", heroElement: .maidenhead)
                    }
                    if let filter = filterText {
                        compactMetadata(filter, symbol: "scope", heroElement: .filterDistance)
                    }
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: true, vertical: false)
            }
            .layoutPriority(2)

            if let server = dashboard.currentServerName.value {
                Button {
                    showsServerPicker = true
                } label: {
                    HStack(spacing: 8) {
                        DashboardMarqueeText(server)
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
                            .clipped()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(fullscreenBackgroundColor.opacity(0.72))
                    }
                    .foregroundStyle(fullscreenBackgroundColor)
                    .allowsHitTesting(false)
                }
                .buttonStyle(.plain)
                .contentShape(.rect)
                .padding(.horizontal, 14)
                .frame(minWidth: 140, maxWidth: 240, minHeight: 40, maxHeight: 40, alignment: .leading)
                .background(Color.accentColor, in: .rect(cornerRadius: 13))
                .highPriorityGesture(
                    TapGesture().onEnded { showsServerPicker = true }
                )
                .accessibilityLabel("切换服务器")
                .accessibilityValue("当前服务器 \(server)")
                .accessibilityIdentifier("dashboard-fullscreen-server-picker")
            }

            Spacer(minLength: 6)

            visualModeSwitch
                .opacity(showsExpandedContent ? 1 : 0)

            HStack(spacing: 7) {
                Circle().fill(.green).frame(width: 7, height: 7)
                Text(deviceName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.white.opacity(0.07), in: .rect(cornerRadius: 13))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("当前设备 \(deviceName)，已连接")
            .opacity(showsExpandedContent ? 1 : 0)
        }
        .frame(height: 46)
    }

    private var fullscreenBackgroundColor: Color {
        Color(red: 0.065, green: 0.07, blue: 0.085)
    }

    private var speakerPanel: some View {
        Group {
            if let target = presentation.target {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: target.isSpeaking ? "speaker.wave.2.fill" : "clock.arrow.circlepath")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(target.isSpeaking ? Color.accentColor : .white.opacity(0.36))
                            .frame(width: 26, height: 26)
                            .contentTransition(
                                accessibilityReduceMotion ? .identity : .symbolEffect(.replace)
                            )
                            .symbolEffect(.variableColor.iterative, isActive: target.isSpeaking)
                            .symbolEffect(.bounce, value: target.callsign)
                            .animation(speakerAnimation, value: target.isSpeaking)
                        Text(target.callsign)
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(target.isSpeaking ? .white : .white.opacity(0.38))
                            .id(target.callsign.uppercased())
                            .transition(speakerItemTransition)
                            .animation(speakerAnimation, value: target.isSpeaking)
                    }
                    .matchedGeometryEffect(
                        id: DashboardHeroElement.speaker,
                        in: heroNamespace,
                        properties: .frame,
                        anchor: .leading,
                        isSource: false
                    )
                    .animation(speakerAnimation, value: target.callsign)
                    .frame(height: 48, alignment: .leading)

                    locationSummary(target)
                        .padding(.top, 8)
                        .frame(height: 32, alignment: .top)

                    audioMonitorRow
                        .padding(.top, 8)

                    recentSpeakers
                        .padding(.top, 8)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            } else {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "等待讲话",
                        systemImage: "speaker.slash",
                        description: Text("收到讲话活动后将在这里持续保留。")
                    )
                    .foregroundStyle(.white)
                    audioMonitorRow
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground)
        .clipShape(.rect(cornerRadius: 23))
    }

    private func locationSummary(_ target: DashboardFullscreenTarget) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .foregroundStyle(target.isSpeaking ? Color.accentColor : .white.opacity(0.36))
            DashboardMarqueeText(areaName ?? String(localized: "位置未知"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(target.isSpeaking ? .white.opacity(0.72) : .white.opacity(0.34))
                .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20, alignment: .leading)
                .clipped()
                .id("\(target.callsign.uppercased())-\(areaName ?? "unknown")")
                .transition(speakerItemTransition)
                .animation(speakerAnimation, value: target.isSpeaking)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .animation(speakerAnimation.delay(accessibilityReduceMotion ? 0 : 0.06), value: target.callsign)
    }

    private var recentSpeakers: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("刚刚讲话", systemImage: "clock.arrow.circlepath")
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.42))
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(presentation.recentSpeakers.prefix(10), id: \.id) { item in
                        historyRow(item)
                            .transition(historyRowTransition)
                    }
                }
                .animation(historyListAnimation, value: presentation.recentSpeakers.map(\.id))
            }
            .scrollIndicators(.visible)
        }
    }

    private func historyRow(_ item: DashboardFullscreenHistoryItem) -> some View {
        HStack(spacing: 8) {
            Text(String(item.callsign.prefix(2)).uppercased())
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Color.accentColor)
                .frame(width: 23, height: 23)
                .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 7))
            Text(item.callsign)
                .font(.caption2.weight(.semibold).monospaced())
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(historyAreaNames[historyKey(item.callsign)] ?? String(localized: "位置未知"))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 92, alignment: .trailing)
        }
        .frame(height: 29)
    }

    private var historyAreaResolutionID: String {
        presentation.recentSpeakers.map { item in
            let coordinate = item.coordinate.map { "\($0.latitude),\($0.longitude)" } ?? "none"
            return "\(historyKey(item.callsign)):\(coordinate)"
        }
        .joined(separator: "|")
    }

    private var targetAreaResolutionID: String {
        guard let target = presentation.target else { return "none" }
        let coordinate = target.coordinate.map { "\($0.latitude),\($0.longitude)" } ?? "none"
        return "\(historyKey(target.callsign)):\(coordinate)"
    }

    private func resolveHistoryAreaNames() async {
        var resolved: [String: String] = [:]
        for item in presentation.recentSpeakers.prefix(10) {
            guard !Task.isCancelled else { return }
            let key = historyKey(item.callsign)
            if let retainedArea = retainedAreaNames[key] {
                resolved[key] = retainedArea
                continue
            }
            let cached = await speakerLocationStore.location(for: item.callsign)
            if cached?.coordinate == item.coordinate, let cachedArea = cached?.areaName {
                resolved[key] = cachedArea
                retainedAreaNames[key] = cachedArea
                continue
            }
            guard let coordinate = item.coordinate else {
                resolved[key] = String(localized: "位置未知")
                continue
            }
            let area = await areaResolver.areaName(for: coordinate)
            resolved[key] = area ?? String(localized: "位置未知")
            if let area {
                retainedAreaNames[key] = area
                await speakerLocationStore.save(
                    DashboardSpeakerLocation(
                        callsign: item.callsign,
                        coordinate: coordinate,
                        grid: nil,
                        areaName: area,
                        updatedAt: .now
                    )
                )
            }
        }
        guard !Task.isCancelled else { return }
        historyAreaNames = resolved
    }

    private func historyKey(_ callsign: String) -> String {
        callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var historyRowTransition: AnyTransition {
        accessibilityReduceMotion
            ? .opacity
            : .move(edge: .top).combined(with: .opacity)
    }

    private var historyListAnimation: Animation? {
        accessibilityReduceMotion ? nil : .snappy(duration: 0.32)
    }

    @ViewBuilder
    private var visualPanel: some View {
        switch visualMode {
        case .bearing:
            DashboardBearingView(target: presentation.target)
                .transition(.opacity)
        case .map:
            DashboardTrackingMap(
                ownCoordinate: ownCoordinate,
                target: presentation.target
            )
            .transition(.opacity)
        }
    }

    private var filterText: String? {
        guard let filter = dashboard.filterDistance.value else { return nil }
        switch filter {
        case .disabled: return "OFF"
        case .kilometers(let value): return "\(value)km"
        }
    }

    private var audioMonitorRow: some View {
        HStack(spacing: 10) {
            DashboardAudioWaveform(
                buffer: audioMonitor.oscilloscopeBuffer,
                isReceiving: audioMonitor.isReceiving
            )
            .frame(maxWidth: .infinity)

            Button {
                audioMonitor.setSoundEnabled(!audioMonitor.isSoundEnabled)
            } label: {
                Image(systemName: audioMonitor.isSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(audioMonitor.isSoundEnabled ? .black : .white.opacity(0.86))
                    .frame(width: 44, height: 44)
                    .background(
                        audioMonitor.isSoundEnabled ? Color.accentColor : .white.opacity(0.08),
                        in: .rect(cornerRadius: 13)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 13)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    }
                    .contentTransition(
                        accessibilityReduceMotion ? .identity : .symbolEffect(.replace)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设备声音")
            .accessibilityValue(
                audioMonitor.isSoundEnabled
                    ? String(localized: "已开启")
                    : String(localized: "已关闭")
            )
            .accessibilityIdentifier("dashboard-audio-toggle")
        }
        .frame(height: 54)
    }

    private var visualModeSwitch: some View {
        HStack(spacing: 3) {
            ForEach(VisualMode.allCases, id: \.self) { mode in
                let selected = visualMode == mode
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        visualMode = mode
                    }
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? .black : .white.opacity(0.88))
                        .frame(width: 40, height: 32)
                        .background(
                            selected ? Color.accentColor : .white.opacity(0.08),
                            in: .rect(cornerRadius: 10)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityValue(
                    selected
                        ? String(localized: "已选择")
                        : String(localized: "未选择")
                )
            }
        }
        .padding(3)
        .background(.black.opacity(0.38), in: .rect(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .frame(width: 92)
    }

    private func compactMetadata(
        _ value: String,
        symbol: String,
        heroElement: DashboardHeroElement
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(value)
                .lineLimit(1)
        }
        .matchedGeometryEffect(
            id: heroElement,
            in: heroNamespace,
            properties: .frame,
            anchor: .leading,
            isSource: false
        )
    }

    private var speakerAnimation: Animation {
        accessibilityReduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.34)
    }

    private var expandedContentTransition: AnyTransition {
        accessibilityReduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .bottom))
    }

    private var speakerItemTransition: AnyTransition {
        accessibilityReduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity.combined(with: .move(edge: .bottom))
            )
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 23)
            .fill(.white.opacity(0.045))
            .stroke(.white.opacity(0.09), lineWidth: 1)
    }

    private var fullscreenBackground: some View {
        RadialGradient(
            colors: [Color.accentColor.opacity(0.12), .clear],
            center: UnitPoint(x: 0.72, y: 0.42),
            startRadius: 20,
            endRadius: 310
        )
        .background(Color(red: 0.065, green: 0.07, blue: 0.085))
    }
}

private struct DashboardAudioWaveform: View {
    let buffer: FmoOscilloscopeBuffer
    let isReceiving: Bool
    private let codec = FmoLocalAudioProtocol()

    var body: some View {
        TimelineView(.animation(paused: !isReceiving)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let displayedPoints = codec.oscilloscopeWaveform(
                    from: buffer,
                    at: timeline.date
                )
                let middle = size.height / 2
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: middle))
                baseline.addLine(to: CGPoint(x: size.width, y: middle))
                context.stroke(baseline, with: .color(.white.opacity(0.08)), lineWidth: 0.5)

                guard displayedPoints.count > 1 else { return }
                var path = Path()
                for (index, point) in displayedPoints.enumerated() {
                    let x = size.width * CGFloat(index) / CGFloat(displayedPoints.count - 1)
                    let normalized = max(-1, min(1, CGFloat(point)))
                    let y = middle - normalized * size.height * 0.42
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [.white.opacity(0.52), Color.accentColor]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    ),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .padding(.horizontal, 8)
        .background(.black.opacity(0.22), in: .rect(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .opacity(isReceiving ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("设备音频波形")
        .accessibilityValue(
            isReceiving
                ? String(localized: "正在接收")
                : String(localized: "等待音频")
        )
        .accessibilityIdentifier("dashboard-audio-waveform")
    }

}

private struct DashboardBearingView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let target: DashboardFullscreenTarget?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 23)
                .fill(.white.opacity(0.045))
                .stroke(.white.opacity(0.09), lineWidth: 1)

            if let bearing = target?.bearingDegrees {
                GeometryReader { proxy in
                    let diameter = min(proxy.size.width, proxy.size.height) * 0.78
                    ZStack {
                        Circle()
                            .stroke(Color.accentColor.opacity(0.34), lineWidth: 1)
                        Circle()
                            .stroke(.white.opacity(0.09), lineWidth: 1)
                            .padding(diameter * 0.18)
                        Circle()
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                            .padding(diameter * 0.36)
                        tickMarks
                        cardinalLabels
                        DashboardCompassPointerShape()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 1, green: 0.72, blue: 0.38), .accentColor],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay {
                                DashboardCompassPointerShape()
                                    .stroke(.white.opacity(0.14), lineWidth: 1)
                            }
                            .frame(width: diameter * 0.29, height: diameter * 0.29)
                            .rotationEffect(.degrees(bearing))
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 18, y: 10)
                            .animation(
                                accessibilityReduceMotion ? nil : .smooth(duration: 0.8),
                                value: bearing
                            )
                    }
                    .frame(width: diameter, height: diameter)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }

                VStack {
                    HStack(alignment: .top, spacing: 8) {
                        Text(target?.cardinalDirection ?? "")
                            .foregroundStyle(Color.accentColor)
                            .font(.headline.weight(.semibold))
                        Text("\(Int(bearing.rounded()))°")
                            .font(.headline.weight(.semibold).monospacedDigit())
                            .contentTransition(.numericText())
                            .animation(metricAnimation, value: Int(bearing.rounded()))
                        Spacer()
                        if let distance = target?.distanceKilometers {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(distance.formatted(.number.precision(.fractionLength(0))))
                                    .font(.headline.weight(.semibold).monospacedDigit())
                                    .contentTransition(.numericText())
                                    .animation(metricAnimation, value: Int(distance.rounded()))
                                Text("km")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(20)
            } else {
                ContentUnavailableView(
                    "方位暂不可用",
                    systemImage: "location.slash",
                    description: Text("需要我的 FMO 坐标和讲话者位置。")
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var tickMarks: some View {
        ForEach(0..<36, id: \.self) { index in
            Capsule()
                .fill(.white.opacity(index.isMultiple(of: 3) ? 0.42 : 0.18))
                .frame(width: 1, height: index.isMultiple(of: 3) ? 9 : 5)
                .offset(y: -112)
                .rotationEffect(.degrees(Double(index) * 10))
        }
    }

    private var cardinalLabels: some View {
        ZStack {
            Text("N").offset(y: -91).foregroundStyle(Color.accentColor)
            Text("E").offset(x: 91)
            Text("S").offset(y: 91)
            Text("W").offset(x: -91)
        }
        .font(.caption.bold())
        .foregroundStyle(.white.opacity(0.35))
    }

    private var accessibilityText: String {
        guard let target, let bearing = target.bearingDegrees else {
            return String(localized: "讲话者方位暂不可用")
        }
        if let distance = target.distanceKilometers {
            return String(
                localized: "\(target.callsign) 位于\(target.cardinalDirection ?? "")方向，\(Int(bearing.rounded()))度，约 \(Int(distance.rounded())) 公里"
            )
        }
        return String(
            localized: "\(target.callsign) 位于\(target.cardinalDirection ?? "")方向，\(Int(bearing.rounded()))度"
        )
    }

    private var metricAnimation: Animation? {
        accessibilityReduceMotion ? nil : .smooth(duration: 0.55)
    }
}

private struct DashboardCompassPointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.02))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.94, y: rect.minY + rect.height * 0.92))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.72))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.minY + rect.height * 0.92))
        path.closeSubpath()
        return path
    }
}

private struct DashboardTrackingMap: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let ownCoordinate: GeoCoordinate?
    let target: DashboardFullscreenTarget?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var tracksTarget = true

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                if let ownCoordinate {
                    Annotation("我的 FMO", coordinate: ownCoordinate.clCoordinate) {
                        Circle()
                            .fill(.blue)
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 18, height: 18)
                    }
                }
                if let targetCoordinate = target?.coordinate {
                    if case .maidenhead = target?.source {
                        MapCircle(center: targetCoordinate.clCoordinate, radius: 5_000)
                            .foregroundStyle(Color.accentColor.opacity(0.16))
                            .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
                    }
                    Annotation(target?.callsign ?? String(localized: "讲话者"), coordinate: targetCoordinate.clCoordinate) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(width: 38, height: 38)
                            .background(Color.accentColor, in: .rect(cornerRadius: 12))
                    }
                    if let ownCoordinate {
                        MapPolyline(coordinates: [ownCoordinate.clCoordinate, targetCoordinate.clCoordinate])
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .clipShape(.rect(cornerRadius: 23))
            .simultaneousGesture(
                DragGesture(minimumDistance: 4).onChanged { _ in
                    tracksTarget = false
                }
            )
            .simultaneousGesture(
                MagnifyGesture().onChanged { _ in
                    tracksTarget = false
                }
            )

            if let distance = target?.distanceKilometers {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(distance.formatted(.number.precision(.fractionLength(0))))
                        .font(.headline.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("km")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(.black.opacity(0.76), in: .rect(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(14)
                .animation(
                    accessibilityReduceMotion ? nil : .smooth(duration: 0.55),
                    value: Int(distance.rounded())
                )
                .accessibilityLabel("距离 \(Int(distance.rounded())) 公里")
            }

            HStack {
                Button {
                    tracksTarget.toggle()
                } label: {
                    Label("追踪", systemImage: tracksTarget ? "scope" : "scope")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tracksTarget ? .black : .white)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(
                            tracksTarget ? Color.accentColor : .black.opacity(0.76),
                            in: .rect(cornerRadius: 13)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(.white.opacity(tracksTarget ? 0.12 : 0.28), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityValue(
                    tracksTarget
                        ? String(localized: "已开启")
                        : String(localized: "已关闭")
                )
                Spacer()
                Button {
                    tracksTarget = true
                    fitBoth(animated: true)
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.76), in: .rect(cornerRadius: 13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(.white.opacity(0.28), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重新框选我的位置和讲话者")
            }
            .padding(14)
        }
        .background(.white.opacity(0.045), in: .rect(cornerRadius: 23))
        .onAppear { fitBoth(animated: false) }
        .onChange(of: target?.coordinate) { _, _ in
            guard tracksTarget else { return }
            fitBoth(animated: true)
        }
        .onChange(of: tracksTarget) { _, enabled in
            guard enabled else { return }
            fitBoth(animated: true)
        }
    }

    private func fitBoth(animated: Bool) {
        guard let targetCoordinate = target?.coordinate else { return }
        let coordinates = [ownCoordinate, targetCoordinate].compactMap { $0 }
        guard !coordinates.isEmpty else { return }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLatitude = latitudes.min(), let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(), let maxLongitude = longitudes.max() else { return }
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.08, (maxLatitude - minLatitude) * 1.45),
                longitudeDelta: max(0.08, (maxLongitude - minLongitude) * 1.45)
            )
        )
        let update = { cameraPosition = .region(region) }
        if animated {
            withAnimation(.smooth(duration: 0.8), update)
        } else {
            update()
        }
    }
}

struct DashboardMarqueeText: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let text: String
    @State private var measuredWidth: CGFloat = 0
    @State private var startedAt = Date.now

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        GeometryReader { proxy in
            let overflows = measuredWidth > proxy.size.width + 1
            Group {
                if overflows, !accessibilityReduceMotion, !disablesAnimationForUITests {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        let gap: CGFloat = 24
                        let travel = measuredWidth + gap
                        let pause: TimeInterval = 1.2
                        let speed: CGFloat = 24
                        let movingDuration = TimeInterval(travel / speed)
                        let cycleDuration = pause + movingDuration
                        let elapsed = max(0, context.date.timeIntervalSince(startedAt))
                            .truncatingRemainder(dividingBy: cycleDuration)
                        let offset = elapsed <= pause
                            ? CGFloat.zero
                            : -min(travel, CGFloat(elapsed - pause) * speed)
                        HStack(spacing: gap) {
                            marqueeLabel
                            marqueeLabel.accessibilityHidden(true)
                        }
                        .offset(x: offset)
                    }
                } else {
                    marqueeLabel
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .overlay(alignment: .leading) {
            marqueeLabel
                .fixedSize(horizontal: true, vertical: false)
                .opacity(0)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: DashboardMarqueeWidthKey.self,
                            value: proxy.size.width
                        )
                    }
                }
                .accessibilityHidden(true)
        }
        .onPreferenceChange(DashboardMarqueeWidthKey.self) { measuredWidth = $0 }
        .onChange(of: text) { _, _ in startedAt = .now }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .clipped()
    }

    private var marqueeLabel: some View {
        Text(text)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var disablesAnimationForUITests: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["FMO_UI_TEST_SCENARIO"] != nil
#else
        false
#endif
    }
}

private struct DashboardMarqueeWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@MainActor
protocol DashboardAreaResolving: Sendable {
    func areaName(for coordinate: GeoCoordinate) async -> String?
}

@MainActor
final class MapKitDashboardAreaResolver: DashboardAreaResolving {
    func areaName(for coordinate: GeoCoordinate) async -> String? {
        guard let request = MKReverseGeocodingRequest(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        ) else { return nil }
        request.preferredLocale = Locale(identifier: "zh_CN")
        guard let item = try? await request.mapItems.first else { return nil }
        return item.addressRepresentations?.cityWithContext
            ?? item.address?.shortAddress
            ?? item.name
    }
}

@MainActor
enum DashboardOrientation {
    static func request(_ orientations: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

private extension GeoCoordinate {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
