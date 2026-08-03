import SwiftUI

struct FmoNetworkView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.sectionSpacing) {
                FeatureSummaryCard(
                    title: "FMO 网络",
                    subtitle: "台站、事件与可信网络状态集中在这里。",
                    symbol: "globe.asia.australia",
                    action: "配置 APRS 后使用"
                )
                FeatureLinkRow(title: "台站与服务器", subtitle: "搜索、收藏和查看数据年龄", symbol: "person.2")
                FeatureLinkRow(title: "APRS 消息", subtitle: "发送消息并跟踪 ACK", symbol: "message")
            }
            .padding(AppTheme.pageSpacing)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("FMO 网络")
    }
}

struct QsoHomeView: View {
    var body: some View {
        ContentUnavailableView {
            Label("尚未导入 QSO", systemImage: "book.closed")
        } description: {
            Text("从 FMO 官方后台导出数据库后，可在这里验签、查询和导出 ADIF。")
        } actions: {
            Button("选择导出文件") {}
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .foregroundStyle(.black)
                .disabled(true)
        }
        .navigationTitle("QSO")
    }
}

struct SettingsHomeView: View {
    var body: some View {
        List {
            Section("应用") {
                Label("通知与系统集成", systemImage: "bell")
                Label("外观与显示", systemImage: "circle.lefthalf.filled")
            }
            Section("隐私与安全") {
                Label("权限与数据使用", systemImage: "hand.raised")
                Label("诊断数据", systemImage: "stethoscope")
            }
            Section("关于") {
                LabeledContent("版本", value: "0.1.0")
                LabeledContent("技术基线", value: "iOS 26 · Swift 6")
            }
        }
        .navigationTitle("设置")
    }
}

private struct FeatureSummaryCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let symbol: String
    let action: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
            Text(action)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

private struct FeatureLinkRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "lock.fill").foregroundStyle(.tertiary)
        }
        .appCard()
    }
}
