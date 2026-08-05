import SwiftUI

struct DeviceDashboardSummaryView: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            callsign
            facts
            relayCapsule
        }
    }

    @ViewBuilder
    private var callsign: some View {
        if let callsign = snapshot.callsign.currentValue {
            Text(callsign)
                .font(.largeTitle.bold().monospaced())
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .accessibilityLabel("呼号 \(callsign)")
                .accessibilityIdentifier("dashboard-callsign")
        }
    }

    @ViewBuilder
    private var facts: some View {
        let items = factItems
        if !items.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    factItemsView(items)
                }
                VStack(alignment: .leading, spacing: 8) {
                    factItemsView(items)
                }
            }
        }
    }

    @ViewBuilder
    private func factItemsView(_ items: [FactItem]) -> some View {
        ForEach(items) { item in
            Label(item.value, systemImage: item.symbol)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityLabel("当前服务器 \(server)")
                        .accessibilityIdentifier("dashboard-server-name")
                }

                if let activity {
                    activityRow(
                        kind: activity.kind,
                        symbol: activity.symbol,
                        callsign: activity.callsign,
                        detail: activity.detail
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.64), in: .rect(cornerRadius: 18))
        }
    }

    private func activityRow(
        kind: ActivityKind,
        symbol: String,
        callsign: String,
        detail: String?
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.variableColor.iterative, isActive: snapshot.currentSpeaker.currentValue != nil)
            Text(callsign)
                .font(.headline.monospaced())
            if let detail {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activityAccessibilityLabel(kind: kind, callsign: callsign, detail: detail))
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
                detail: speaker.grid
            )
        }
        if let activity = snapshot.recentLocalActivity.currentValue {
            return ActivityItem(
                kind: .recent,
                symbol: "clock.arrow.circlepath",
                callsign: activity.callsign,
                detail: activity.occurredAt.formatted(.relative(presentation: .named))
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
}

private struct ActivityItem {
    let kind: ActivityKind
    let symbol: String
    let callsign: String
    let detail: String?
}

private enum ActivityKind {
    case speaking
    case recent
}
