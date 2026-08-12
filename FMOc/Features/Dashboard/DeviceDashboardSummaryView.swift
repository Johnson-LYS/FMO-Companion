import SwiftUI

struct DeviceDashboardSummaryView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let snapshot: DashboardSnapshot
    let heroNamespace: Namespace.ID
    let participatesInHero: Bool
    let openFullscreen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            callsign
            facts
            relayCapsule
        }
    }

    private var callsign: some View {
        HStack(alignment: .center, spacing: 12) {
            if let callsign = snapshot.callsign.currentValue {
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
        let server = snapshot.currentServerName.currentValue
        let activity = currentActivity

        if server != nil || activity != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let server {
                    Text(server)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .dashboardHeroSource(
                            .server,
                            in: heroNamespace,
                            isActive: participatesInHero
                        )
                        .accessibilityLabel("当前服务器 \(server)")
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
            if let grid = activity.grid {
                Text(grid)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.52))
            }
            if let occurredAt = activity.occurredAt {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(occurredAt, style: .relative)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.42))
                }
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

        if let maidenhead = snapshot.maidenhead.currentValue {
            items.append(
                FactItem(
                    id: "grid",
                    symbol: "location.fill",
                    value: maidenhead,
                    accessibilityLabel: "梅登黑德网格",
                    accessibilityValue: maidenhead,
                    accessibilityIdentifier: "dashboard-maidenhead-value"
                )
            )
        }

        if let filter = snapshot.filterDistance.currentValue {
            switch filter {
            case .disabled:
                items.append(
                    FactItem(
                        id: "filter",
                        symbol: "scope",
                        value: "OFF",
                        accessibilityLabel: "服务器过滤距离",
                        accessibilityValue: "已关闭",
                        accessibilityIdentifier: "dashboard-filter-value"
                    )
                )
            case .kilometers(let value):
                items.append(
                    FactItem(
                        id: "filter",
                        symbol: "scope",
                        value: "\(value) km",
                        accessibilityLabel: "服务器过滤距离",
                        accessibilityValue: "\(value) 公里",
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
                occurredAt: nil
            )
        }
        if let activity = snapshot.recentLocalActivity.currentValue {
            return ActivityItem(
                kind: .recent,
                symbol: "clock.arrow.circlepath",
                callsign: activity.callsign,
                grid: nil,
                occurredAt: activity.occurredAt
            )
        }
        return nil
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
    let occurredAt: Date?

    var id: String {
        callsign.uppercased()
    }

    var accessibilityDetail: String? {
        switch kind {
        case .speaking:
            grid
        case .recent:
            occurredAt?.formatted(.relative(presentation: .named))
        }
    }
}

private enum ActivityKind: Equatable {
    case speaking
    case recent
}
