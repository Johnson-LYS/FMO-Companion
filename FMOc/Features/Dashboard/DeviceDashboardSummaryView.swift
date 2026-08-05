import SwiftUI

struct DeviceDashboardSummaryView: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        HStack(spacing: 0) {
            metric(
                title: "GEO 会话",
                value: "已连接",
                detail: "公开局域网接口",
                symbol: "checkmark.circle.fill"
            )

            Divider()
                .padding(.horizontal, 14)

            metric(
                title: "梅登黑德",
                value: snapshot.maidenhead.value ?? "不可用",
                detail: maidenheadDetail,
                symbol: "grid"
            )
            .accessibilityIdentifier("dashboard-maidenhead-value")
        }
        .padding(14)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    private func metric(
        title: LocalizedStringKey,
        value: String,
        detail: LocalizedStringKey,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospaced())
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var maidenheadDetail: LocalizedStringKey {
        switch snapshot.maidenhead {
        case .available:
            "由 FMO 坐标换算"
        case .stale:
            "上次连接时换算"
        case .unknown:
            "尚未读取坐标"
        case .unsupported:
            "设备暂不支持"
        case .rejected:
            "坐标数据不可用"
        }
    }
}
