import ActivityKit
import SwiftUI
import WidgetKit

struct FmoDashboardLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FmoDashboardActivityAttributes.self) { context in
            FmoDashboardLockScreenView(context: context)
                .activityBackgroundTint(BrandColor.orange.opacity(0.14))
                .activitySystemActionForegroundColor(BrandColor.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    callsign(context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    connection(context.state.connection, includesText: true)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        server(context.state)
                        activity(context.state)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.activity?.kind == .speaking
                      ? "speaker.wave.2.fill"
                      : "antenna.radiowaves.left.and.right")
                    .foregroundStyle(BrandColor.orange)
                    .accessibilityLabel(
                        context.state.activity?.kind == .speaking
                            ? String(localized: "当前讲话")
                            : "FMO"
                    )
            } compactTrailing: {
                if let item = context.state.activity, item.kind == .speaking {
                    Text(item.callsign)
                        .font(.caption2.bold().monospaced())
                        .lineLimit(1)
                } else {
                    connection(context.state.connection, includesText: false)
                }
            } minimal: {
                Image(systemName: context.state.activity?.kind == .speaking
                      ? "speaker.wave.2.fill"
                      : connectionSymbol(context.state.connection))
                    .foregroundStyle(BrandColor.orange)
                    .accessibilityLabel(connectionLabel(context.state.connection))
            }
            .keylineTint(BrandColor.orange)
        }
    }

    @ViewBuilder
    private func callsign(_ state: FmoDashboardActivityAttributes.ContentState) -> some View {
        if let callsign = state.callsign {
            Text(callsign)
                .font(.headline.bold().monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel("呼号 \(callsign)")
        } else {
            Text("FMO")
                .font(.headline.bold())
        }
    }

    @ViewBuilder
    private func server(_ state: FmoDashboardActivityAttributes.ContentState) -> some View {
        if let serverName = state.serverName {
            Text(serverName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityLabel("当前服务器 \(serverName)")
        }
    }

    @ViewBuilder
    private func activity(_ state: FmoDashboardActivityAttributes.ContentState) -> some View {
        if let item = state.activity {
            HStack(spacing: 7) {
                Image(systemName: item.kind == .speaking ? "speaker.wave.2.fill" : "clock.arrow.circlepath")
                    .foregroundStyle(BrandColor.orange)
                Text(item.callsign)
                    .font(.caption.bold().monospaced())
                if let grid = item.grid {
                    Label(grid, systemImage: "location.fill")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                } else if let occurredAt = item.occurredAt {
                    Text(occurredAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(activityLabel(item))
        }
    }

    private func connection(
        _ state: FmoDashboardActivityAttributes.ContentState.Connection,
        includesText: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: connectionSymbol(state))
            if includesText {
                Text(connectionLabel(state))
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(state == .connected ? BrandColor.orange : .secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(connectionLabel(state))
    }

    private func connectionSymbol(
        _ state: FmoDashboardActivityAttributes.ContentState.Connection
    ) -> String {
        switch state {
        case .connected: "wave.3.right"
        case .stale: "clock.badge.exclamationmark"
        case .disconnected: "wifi.slash"
        }
    }

    private func connectionLabel(
        _ state: FmoDashboardActivityAttributes.ContentState.Connection
    ) -> String {
        switch state {
        case .connected: String(localized: "已连接")
        case .stale: String(localized: "已过期")
        case .disconnected: String(localized: "未连接")
        }
    }

    private func activityLabel(
        _ item: FmoDashboardActivityAttributes.ContentState.ActivityItem
    ) -> String {
        switch item.kind {
        case .speaking: String(localized: "当前讲话 \(item.callsign)")
        case .recent: String(localized: "最近讲话活动 \(item.callsign)")
        }
    }
}

private struct FmoDashboardLockScreenView: View {
    let context: ActivityViewContext<FmoDashboardActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let callsign = context.state.callsign {
                    Text(callsign)
                        .font(.title2.bold().monospaced())
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .accessibilityLabel("呼号 \(callsign)")
                } else {
                    Text("FMO")
                        .font(.title2.bold())
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    connectionStatus
                    Text(context.state.updatedAt, style: .relative)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("更新时间")
                }
            }

            if let maidenhead = context.state.maidenhead {
                Label(maidenhead, systemImage: "location.fill")
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("梅登黑德网格 \(maidenhead)")
            }

            if context.state.serverName != nil || context.state.activity != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let serverName = context.state.serverName {
                        Text(serverName)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .accessibilityLabel("当前服务器 \(serverName)")
                    }
                    activityRow
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.54), in: .rect(cornerRadius: 16))
            }
        }
        .padding(16)
    }

    private var connectionStatus: some View {
        HStack(spacing: 5) {
            Image(systemName: connectionSymbol)
            if context.state.connection != .connected {
                Text(connectionLabel)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(context.state.connection == .connected ? BrandColor.orange : .secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(connectionLabel)
    }

    @ViewBuilder
    private var activityRow: some View {
        if let item = context.state.activity {
            HStack(spacing: 8) {
                Image(systemName: item.kind == .speaking ? "speaker.wave.2.fill" : "clock.arrow.circlepath")
                    .foregroundStyle(BrandColor.orange)
                Text(item.callsign)
                    .font(.subheadline.bold().monospaced())
                if let grid = item.grid {
                    Label(grid, systemImage: "location.fill")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else if let occurredAt = item.occurredAt {
                    Text(occurredAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                item.kind == .speaking
                    ? String(localized: "当前讲话 \(item.callsign)")
                    : String(localized: "最近讲话活动 \(item.callsign)")
            )
        }
    }

    private var connectionSymbol: String {
        switch context.state.connection {
        case .connected: "wave.3.right"
        case .stale: "clock.badge.exclamationmark"
        case .disconnected: "wifi.slash"
        }
    }

    private var connectionLabel: String {
        switch context.state.connection {
        case .connected: String(localized: "已连接")
        case .stale: String(localized: "已过期")
        case .disconnected: String(localized: "未连接")
        }
    }
}

private enum BrandColor {
    static let orange = Color(red: 1, green: 0.533, blue: 0)
}
