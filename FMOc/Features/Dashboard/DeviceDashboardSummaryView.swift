import SwiftUI

struct DeviceDashboardSummaryView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let snapshot: DashboardSnapshot
    @Bindable var audioMonitor: FmoAudioMonitorModel
    let heroNamespace: Namespace.ID
    let participatesInHero: Bool
    let openServerPicker: () -> Void
    let openFullscreen: () -> Void
    private let areaResolver: any DashboardAreaResolving
    private let speakerLocationStore: any DashboardSpeakerLocationStoring
    @State private var speakerAreaNames: [String: String] = [:]

    init(
        snapshot: DashboardSnapshot,
        audioMonitor: FmoAudioMonitorModel,
        areaResolver: any DashboardAreaResolving = MapKitDashboardAreaResolver(),
        speakerLocationStore: any DashboardSpeakerLocationStoring = VolatileDashboardSpeakerLocationStore(),
        heroNamespace: Namespace.ID,
        participatesInHero: Bool,
        openServerPicker: @escaping () -> Void,
        openFullscreen: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.audioMonitor = audioMonitor
        self.areaResolver = areaResolver
        self.speakerLocationStore = speakerLocationStore
        self.heroNamespace = heroNamespace
        self.participatesInHero = participatesInHero
        self.openServerPicker = openServerPicker
        self.openFullscreen = openFullscreen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            callsign
            facts
            relayCapsule
        }
        .task(id: activityLocationID) {
            await resolveActivityArea()
        }
    }

    private var callsign: some View {
        HStack(alignment: .center, spacing: 12) {
            if let callsign = snapshot.callsign.value {
                Text(callsign)
                    .font(.largeTitle.bold().monospaced())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.62)
                    .lineLimit(1)
                    .dashboardHeroSource(
                        .callsign,
                        in: heroNamespace,
                        isActive: participatesInHero
                    )
                    .accessibilityLabel("呼号 \(callsign)")
                    .accessibilityIdentifier("dashboard-callsign")
            }

            Spacer(minLength: 0)

            audioToggle

            Button(action: openFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }
                .padding(.vertical, 3)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开横屏仪表盘")
            .accessibilityIdentifier("dashboard-fullscreen-button")
        }
    }

    private var audioToggle: some View {
        Button {
            audioMonitor.setSoundEnabled(!audioMonitor.isSoundEnabled)
        } label: {
            Image(systemName: audioMonitor.isSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(audioMonitor.isSoundEnabled ? dashboardBackgroundColor : .white.opacity(0.86))
                .frame(width: 38, height: 38)
                .background(
                    audioMonitor.isSoundEnabled ? Color.accentColor : .white.opacity(0.08),
                    in: .rect(cornerRadius: 13)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(.white.opacity(audioMonitor.isSoundEnabled ? 0.08 : 0.10), lineWidth: 1)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("设备声音")
        .accessibilityValue(audioMonitor.isSoundEnabled ? String(localized: "已开启") : String(localized: "已关闭"))
        .accessibilityIdentifier("dashboard-audio-toggle")
    }

    @ViewBuilder
    private var facts: some View {
        let items = factItems
        if !items.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    factItemsView(items)
                }
                VStack(alignment: .leading, spacing: 6) {
                    factItemsView(items)
                }
            }
        }
    }

    @ViewBuilder
    private func factItemsView(_ items: [FactItem]) -> some View {
        ForEach(items) { item in
            HStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 10, height: 10)
                Text(item.value)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.66))
            }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .dashboardHeroSource(
                    item.heroElement,
                    in: heroNamespace,
                    isActive: participatesInHero
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.accessibilityLabel)
                .accessibilityValue(item.accessibilityValue)
                .accessibilityIdentifier(item.accessibilityIdentifier)
        }
    }

    @ViewBuilder
    private var relayCapsule: some View {
        let server = snapshot.currentServerName.value
        let activity = currentActivity

        if server != nil || activity != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let server {
                    Button(action: openServerPicker) {
                        HStack(spacing: 8) {
                            Text(server)
                                .font(.headline.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(dashboardBackgroundColor.opacity(0.72))
                        }
                        .foregroundStyle(dashboardBackgroundColor)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .background(Color.accentColor, in: .rect(cornerRadius: 13))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .dashboardHeroSource(
                        .server,
                        in: heroNamespace,
                        isActive: participatesInHero
                    )
                    .accessibilityLabel("切换服务器")
                    .accessibilityValue("当前服务器 \(server)")
                    .accessibilityIdentifier("dashboard-server-name")
                }

                if let activity {
                    ZStack(alignment: .leading) {
                        activityRow(activity)
                            .id(activity.id)
                            .transition(activityTransition)
                            .dashboardHeroSource(
                                .speaker,
                                in: heroNamespace,
                                isActive: participatesInHero
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .animation(activityAnimation, value: activity.id)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 18))
        }
    }

    private var dashboardBackgroundColor: Color {
        Color(red: 0.065, green: 0.07, blue: 0.085)
    }

    private func activityRow(_ activity: ActivityItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: activity.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .contentTransition(
                    accessibilityReduceMotion ? .identity : .symbolEffect(.replace)
                )
                .animation(activityAnimation, value: activity.symbol)
                .symbolEffect(.variableColor.iterative, isActive: snapshot.currentSpeaker.currentValue != nil)
            Text(activity.callsign)
                .font(.headline.monospaced())
                .foregroundStyle(activity.kind == .speaking ? .white : .white.opacity(0.48))
                .animation(.easeInOut(duration: 0.2), value: activity.kind)
            if let areaName = activity.areaName {
                DashboardMarqueeText(areaName)
                    .font(.caption)
                    .foregroundStyle(activity.kind == .speaking ? .white.opacity(0.66) : .white.opacity(0.38))
                    .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .leading)
                    .animation(.easeInOut(duration: 0.2), value: activity.kind)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            activityAccessibilityLabel(
                kind: activity.kind,
                callsign: activity.callsign,
                detail: activity.accessibilityDetail
            )
        )
    }

    private var activityTransition: AnyTransition {
        if accessibilityReduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    private var activityAnimation: Animation {
        accessibilityReduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.28)
    }

    private func activityAccessibilityLabel(
        kind: ActivityKind,
        callsign: String,
        detail: String?
    ) -> Text {
        switch (kind, detail) {
        case (.speaking, let detail?): Text("当前讲话 \(callsign)，\(detail)")
        case (.speaking, nil): Text("当前讲话 \(callsign)")
        case (.recent, let detail?): Text("最近讲话活动 \(callsign)，\(detail)")
        case (.recent, nil): Text("最近讲话活动 \(callsign)")
        }
    }

    private var factItems: [FactItem] {
        var items: [FactItem] = []

        if let maidenhead = snapshot.maidenhead.value {
            items.append(
                FactItem(
                    id: "grid",
                    symbol: "location.fill",
                    value: maidenhead,
                    accessibilityLabel: String(localized: "梅登黑德网格"),
                    accessibilityValue: maidenhead,
                    accessibilityIdentifier: "dashboard-maidenhead-value"
                )
            )
        }

        if let filter = snapshot.filterDistance.value {
            switch filter {
            case .disabled:
                items.append(
                    FactItem(
                        id: "filter",
                        symbol: "scope",
                        value: "OFF",
                        accessibilityLabel: String(localized: "服务器过滤距离"),
                        accessibilityValue: String(localized: "已关闭"),
                        accessibilityIdentifier: "dashboard-filter-value"
                    )
                )
            case .kilometers(let value):
                items.append(
                    FactItem(
                        id: "filter",
                        symbol: "scope",
                        value: Measurement(value: Double(value), unit: UnitLength.kilometers)
                            .formatted(.measurement(width: .abbreviated, usage: .asProvided)),
                        accessibilityLabel: String(localized: "服务器过滤距离"),
                        accessibilityValue: String(localized: "\(value) 公里"),
                        accessibilityIdentifier: "dashboard-filter-value"
                    )
                )
            }
        }

        return items
    }

    private var currentActivity: ActivityItem? {
        if let speaker = snapshot.currentSpeaker.currentValue {
            return ActivityItem(
                kind: .speaking,
                symbol: "speaker.wave.2.fill",
                callsign: speaker.callsign,
                grid: speaker.grid,
                coordinate: speaker.coordinate,
                areaName: speakerAreaNames[normalizedCallsign(speaker.callsign)]
            )
        }
        if let activity = snapshot.recentLocalActivity.currentValue {
            return ActivityItem(
                kind: .recent,
                symbol: "speaker.slash.fill",
                callsign: activity.callsign,
                grid: activity.grid,
                coordinate: activity.coordinate,
                areaName: speakerAreaNames[normalizedCallsign(activity.callsign)]
            )
        }
        return nil
    }

    private var activityLocationID: String {
        guard let activity = currentActivity else { return "none" }
        let coordinate = activity.coordinate.map { "\($0.latitude),\($0.longitude)" } ?? "none"
        return "\(normalizedCallsign(activity.callsign))-\(activity.grid ?? "none")-\(coordinate)"
    }

    private func resolveActivityArea() async {
        guard let activity = currentActivity else { return }
        let key = normalizedCallsign(activity.callsign)
        guard !key.isEmpty else { return }

        let cached = await speakerLocationStore.location(for: key)
        if let cachedArea = cached?.areaName {
            speakerAreaNames[key] = cachedArea
            return
        }
        let coordinate = activity.coordinate ?? activity.grid.flatMap(MaidenheadGrid.center(of:))
        guard let coordinate,
              let areaName = await areaResolver.areaName(for: coordinate),
              !Task.isCancelled else { return }
        speakerAreaNames[key] = areaName
        await speakerLocationStore.save(
            DashboardSpeakerLocation(
                callsign: key,
                coordinate: coordinate,
                grid: activity.grid,
                areaName: areaName,
                updatedAt: .now
            )
        )
    }

    private func normalizedCallsign(_ callsign: String) -> String {
        callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

private struct FactItem: Identifiable {
    let id: String
    let symbol: String
    let value: String
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityIdentifier: String

    var heroElement: DashboardHeroElement {
        id == "grid" ? .maidenhead : .filterDistance
    }
}

private struct ActivityItem {
    let kind: ActivityKind
    let symbol: String
    let callsign: String
    let grid: String?
    let coordinate: GeoCoordinate?
    let areaName: String?

    var id: String {
        callsign.uppercased()
    }

    var accessibilityDetail: String? {
        areaName
    }
}

private enum ActivityKind: Equatable {
    case speaking
    case recent
}
