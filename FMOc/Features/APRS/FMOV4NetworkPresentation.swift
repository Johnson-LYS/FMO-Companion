import SwiftUI

extension FMOV4NetworkEventKind {
    var title: LocalizedStringResource {
        switch self {
        case .cq: "CQ"
        case .omcq: "OMCQ"
        case .vocal: "语音活动"
        case .online: "上线"
        case .beacon: "位置更新"
        case .station: "服务器广播"
        case .event: "动态事件"
        }
    }

    var shortLabel: String {
        switch self {
        case .cq: "CQ"
        case .omcq: "OM"
        case .vocal: "VO"
        case .online: "ON"
        case .beacon: "BC"
        case .station: "ST"
        case .event: "EV"
        }
    }

    var symbol: String {
        switch self {
        case .cq, .omcq: "megaphone.fill"
        case .vocal: "waveform"
        case .online: "dot.radiowaves.left.and.right"
        case .beacon: "location.fill"
        case .station: "server.rack"
        case .event: "bolt.fill"
        }
    }

    var tint: Color {
        switch self {
        case .cq, .omcq, .event: .orange
        case .vocal, .online: .green
        case .beacon, .station: .secondary
        }
    }
}

struct FMOV4EventRow: View {
    let event: FMOV4NetworkEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.kind.symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(event.kind.tint)
                .frame(width: 36, height: 36)
                .background(event.kind.tint.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let content = event.content, !content.isEmpty {
                    Text(content)
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)
            Text(event.observedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 11)
        .contentShape(.rect)
    }

    private var title: String {
        if let topic = event.topic, !topic.isEmpty {
            return "\(event.callsign) · \(topic)"
        }
        return "\(event.callsign) · \(String(localized: event.kind.title))"
    }
}
