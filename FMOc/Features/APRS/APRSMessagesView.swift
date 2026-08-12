import SwiftData
import SwiftUI

struct APRSMessagesView: View {
    @Bindable var model: APRSMessageModel
    @Query(sort: \APRSMessageRecord.createdAt, order: .reverse)
    private var records: [APRSMessageRecord]
    @State private var showsNewMessage = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 9, height: 9)
                    Text(model.statusText)
                    Spacer()
                    if model.phase == .connecting {
                        ProgressView().controlSize(.small)
                    }
                }
            }

            Section("最近会话") {
                if conversations.isEmpty {
                    ContentUnavailableView(
                        "还没有消息",
                        systemImage: "message",
                        description: Text("可从收藏呼号或手动输入地址开始会话。")
                    )
                    .frame(minHeight: 220)
                } else {
                    ForEach(conversations, id: \.peer) { conversation in
                        NavigationLink {
                            APRSConversationView(peer: conversation.peer, model: model)
                        } label: {
                            conversationRow(conversation)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("删除", systemImage: "trash", role: .destructive) {
                                model.deleteConversation(with: conversation.peer)
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                }
            }
        }
        .navigationTitle("APRS 消息")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("新消息", systemImage: "square.and.pencil") {
                    showsNewMessage = true
                }
                .accessibilityIdentifier("aprs-new-message")
            }
        }
        .sheet(isPresented: $showsNewMessage) {
            APRSNewMessageSheet(model: model)
        }
        .alert("消息提示", isPresented: issueIsPresented) {
            Button("好") { model.lastIssue = nil }
        } message: {
            Text(model.lastIssue ?? String(localized: "请稍后再试"))
        }
    }

    private var conversations: [(peer: TNC2Address, record: APRSMessageRecord)] {
        var seen = Set<TNC2Address>()
        return records.compactMap { record in
            guard seen.insert(record.peer).inserted else { return nil }
            return (record.peer, record)
        }
    }

    private func conversationRow(
        _ conversation: (peer: TNC2Address, record: APRSMessageRecord)
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.peer.formatted)
                    .font(.headline.monospaced())
                Text(conversation.record.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(conversation.record.createdAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .ready: .green
        case .connecting: .orange
        case .unconfigured, .paused, .waitingForNetwork: .secondary
        }
    }

    private var issueIsPresented: Binding<Bool> {
        Binding(get: { model.lastIssue != nil }, set: { if !$0 { model.lastIssue = nil } })
    }
}

private struct APRSConversationView: View {
    let peer: TNC2Address
    @Bindable var model: APRSMessageModel
    @Query private var records: [APRSMessageRecord]
    @SceneStorage private var draft: String

    init(peer: TNC2Address, model: APRSMessageModel) {
        self.peer = peer
        self.model = model
        _draft = SceneStorage(wrappedValue: "", "aprs.messageDraft.\(peer.formatted)")
        let callsign = peer.callsign
        let ssid = Int(peer.ssid)
        _records = Query(
            filter: #Predicate<APRSMessageRecord> {
                $0.peerCallsign == callsign && $0.peerSSID == ssid
            },
            sort: [SortDescriptor(\APRSMessageRecord.createdAt)]
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(records) { record in
                            messageBubble(record)
                                .id(record.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: records.count) { _, _ in
                    if let id = records.last?.id {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("消息", text: $draft, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .textFieldStyle(.roundedBorder)
                Button("发送", systemImage: "arrow.up.circle.fill") {
                    let text = draft
                    Task {
                        if await model.send(text: text, to: peer) {
                            draft = ""
                        }
                    }
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(peer.formatted)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func messageBubble(_ record: APRSMessageRecord) -> some View {
        HStack {
            if record.direction == .outgoing { Spacer(minLength: 50) }
            VStack(alignment: record.direction == .outgoing ? .trailing : .leading, spacing: 4) {
                Text(record.text)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .foregroundStyle(record.direction == .outgoing ? .white : .primary)
                    .background(
                        record.direction == .outgoing
                            ? Color.accentColor
                            : Color(uiColor: .secondarySystemGroupedBackground),
                        in: .rect(cornerRadius: 16)
                    )
                if record.direction == .outgoing {
                    HStack(spacing: 6) {
                        Text(deliveryText(record.status))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if record.status == .unconfirmed {
                            Button("重试") {
                                Task { await model.send(text: record.text, to: peer) }
                            }
                            .font(.caption2.weight(.semibold))
                        }
                    }
                }
            }
            if record.direction == .incoming { Spacer(minLength: 50) }
        }
    }

    private func deliveryText(_ status: APRSMessageDeliveryStatus) -> LocalizedStringResource {
        switch status {
        case .sending: "发送中"
        case .waitingAcknowledgement: "等待确认"
        case .acknowledged: "已确认"
        case .unconfirmed: "未确认"
        case .received: ""
        }
    }
}

private struct APRSNewMessageSheet: View {
    @Bindable var model: APRSMessageModel
    @Query(sort: \FavoriteCallsign.createdAt, order: .reverse)
    private var favorites: [FavoriteCallsign]
    @State private var address = ""
    @State private var message = ""
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("输入地址") {
                    TextField("呼号-SSID", text: $address)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("消息", text: $message, axis: .vertical)
                        .lineLimit(1 ... 4)
                    Button("发送") { send(to: address) }
                        .disabled(
                            address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
                if !favorites.isEmpty {
                    Section("收藏联系人") {
                        ForEach(favorites) { favorite in
                            Button {
                                let suffix = favorite.lastSSID.map { "-\($0)" } ?? ""
                                address = favorite.displayCallsign + suffix
                            } label: {
                                Text(favorite.displayCallsign)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("新消息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("地址不可用", isPresented: Binding(
                get: { issue != nil },
                set: { if !$0 { issue = nil } }
            )) {
                Button("好") { issue = nil }
            } message: {
                Text(issue ?? String(localized: "请输入有效的呼号与 SSID"))
            }
        }
    }

    private func send(to value: String) {
        do {
            let peer = try APRSMessageCodec().parseAddress(value)
            let text = message
            Task {
                if await model.send(text: text, to: peer) {
                    dismiss()
                }
            }
        } catch {
            issue = String(localized: "请输入有效的呼号与 SSID")
        }
    }
}
