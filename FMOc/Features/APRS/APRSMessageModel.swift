import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class APRSMessageModel {
    enum Phase: Equatable {
        case unconfigured
        case paused
        case connecting
        case ready
        case waitingForNetwork
    }

    nonisolated struct Policy: Sendable {
        var retryDelay: Duration = .seconds(30)
        var maximumRetryCount = 2
        var reconnectDelays: [Duration] = [.seconds(1), .seconds(3), .seconds(10), .seconds(30)]
    }

    private let client: any APRSISMessaging
    private let codec: APRSMessageCodec
    private let endpoint: APRSISEndpoint
    private let policy: Policy
    private var modelContext: ModelContext?
    private var identity: ReceiveOnlyAPRSIdentity?
    private var isActive = false
    private var sessionTask: Task<Void, Never>?
    private var pendingTasks: [UUID: Task<Void, Never>] = [:]
    private var sessionGeneration = 0

    var phase: Phase = .unconfigured
    var serverCallsign: String?
    var lastIssue: String?
    var controlMessageHandler: ((APRSMessageEnvelope) -> Bool)?

    init(
        client: any APRSISMessaging,
        codec: APRSMessageCodec = APRSMessageCodec(),
        endpoint: APRSISEndpoint = .asia,
        policy: Policy = Policy()
    ) {
        self.client = client
        self.codec = codec
        self.endpoint = endpoint
        self.policy = policy
    }

    var statusText: String {
        switch phase {
        case .unconfigured: String(localized: "请先设置 APRS 身份")
        case .paused: String(localized: "打开 App 后接收消息")
        case .connecting: String(localized: "正在连接")
        case .ready: String(localized: "已连接")
        case .waitingForNetwork: String(localized: "等待网络")
        }
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func setIdentity(_ identity: ReceiveOnlyAPRSIdentity?) async {
        guard self.identity != identity else { return }
        self.identity = identity
        await restartSession(markPendingUnconfirmed: true)
    }

    func setActive(_ isActive: Bool) async {
        guard self.isActive != isActive else { return }
        self.isActive = isActive
        await restartSession(markPendingUnconfirmed: !isActive)
    }

    @discardableResult
    func send(text: String, to peer: TNC2Address) async -> Bool {
        guard let identity, let modelContext else {
            lastIssue = String(localized: "请先设置 APRS 身份")
            return false
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageID: APRSMessageID
        do {
            messageID = try makeMessageID()
            _ = try codec.encodeInformation(
                addressee: peer,
                payload: .message(text: trimmed, id: messageID)
            )
        } catch APRSMessageProtocolError.emptyText {
            lastIssue = String(localized: "请输入消息内容")
            return false
        } catch APRSMessageProtocolError.textTooLong {
            lastIssue = String(localized: "消息最多 60 字节")
            return false
        } catch APRSMessageProtocolError.unsupportedTextCharacter {
            lastIssue = String(localized: "消息不能包含换行或 { 符号")
            return false
        } catch {
            lastIssue = String(localized: "消息内容无法发送")
            return false
        }

        let record = APRSMessageRecord(
            peer: peer,
            direction: .outgoing,
            text: trimmed,
            messageID: messageID,
            status: .sending
        )
        modelContext.insert(record)
        try? modelContext.save()

        guard phase == .ready else {
            record.status = .unconfirmed
            try? modelContext.save()
            lastIssue = String(localized: "网络尚未连接，消息未发送")
            return true
        }
        await transmit(record, identity: identity, peer: peer, messageID: messageID)
        return true
    }

    func deleteConversation(with peer: TNC2Address) {
        guard let modelContext else { return }
        let callsign = peer.callsign
        let ssid = Int(peer.ssid)
        let descriptor = FetchDescriptor<APRSMessageRecord>(
            predicate: #Predicate { $0.peerCallsign == callsign && $0.peerSSID == ssid }
        )
        guard let records = try? modelContext.fetch(descriptor) else { return }
        for record in records {
            pendingTasks.removeValue(forKey: record.id)?.cancel()
            modelContext.delete(record)
        }
        try? modelContext.save()
    }

    private func restartSession(markPendingUnconfirmed: Bool) async {
        sessionGeneration += 1
        sessionTask?.cancel()
        sessionTask = nil
        await client.disconnect()
        serverCallsign = nil
        if markPendingUnconfirmed {
            markAllPendingUnconfirmed()
        }
        guard identity != nil else {
            phase = .unconfigured
            return
        }
        guard isActive else {
            phase = .paused
            return
        }
        let generation = sessionGeneration
        sessionTask = Task { [weak self] in
            await self?.runSession(generation: generation)
        }
    }

    private func runSession(generation: Int) async {
        guard let identity else { return }
        var retryIndex = 0
        while !Task.isCancelled, generation == sessionGeneration, isActive {
            phase = .connecting
            do {
                let stream = await client.events(identity: identity, endpoint: endpoint)
                for try await event in stream {
                    guard generation == sessionGeneration, isActive else { return }
                    switch event {
                    case let .sessionReady(serverCallsign):
                        self.serverCallsign = serverCallsign
                        phase = .ready
                        retryIndex = 0
                    case let .message(envelope):
                        await handle(envelope, identity: identity)
                    case .rejectedPacket:
                        break
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                lastIssue = String(localized: "消息网络暂时不可用")
            }
            guard generation == sessionGeneration, isActive else { return }
            phase = .waitingForNetwork
            let delays = policy.reconnectDelays
            guard !delays.isEmpty else { return }
            let delay = delays[min(retryIndex, delays.count - 1)]
            retryIndex = min(retryIndex + 1, delays.count - 1)
            try? await Task.sleep(for: delay)
        }
    }

    private func transmit(
        _ record: APRSMessageRecord,
        identity: ReceiveOnlyAPRSIdentity,
        peer: TNC2Address,
        messageID: APRSMessageID
    ) async {
        do {
            let packet = try codec.encodePacket(
                source: TNC2Address(callsign: identity.callsign, ssid: identity.ssid),
                addressee: peer,
                payload: .message(text: record.text, id: messageID)
            )
            try await client.send(packet: packet)
            record.status = .waitingAcknowledgement
            try? modelContext?.save()
            let recordID = record.id
            pendingTasks[recordID] = Task { [weak self] in
                await self?.retry(recordID: recordID, packet: packet)
            }
        } catch {
            record.status = .unconfirmed
            try? modelContext?.save()
            lastIssue = String(localized: "消息发送失败")
        }
    }

    private func retry(recordID: UUID, packet: String) async {
        for _ in 0 ..< policy.maximumRetryCount {
            do { try await Task.sleep(for: policy.retryDelay) } catch { return }
            guard
                isActive,
                phase == .ready,
                let record = fetchRecord(id: recordID),
                record.status == .waitingAcknowledgement
            else { return }
            do {
                try await client.send(packet: packet)
            } catch {
                record.status = .unconfirmed
                try? modelContext?.save()
                pendingTasks.removeValue(forKey: recordID)
                return
            }
        }
        if let record = fetchRecord(id: recordID), record.status == .waitingAcknowledgement {
            record.status = .unconfirmed
            try? modelContext?.save()
        }
        pendingTasks.removeValue(forKey: recordID)
    }

    private func handle(
        _ envelope: APRSMessageEnvelope,
        identity: ReceiveOnlyAPRSIdentity
    ) async {
        if controlMessageHandler?(envelope) == true {
            return
        }
        switch envelope.payload {
        case let .message(text, messageID):
            if !isDuplicate(peer: envelope.source, messageID: messageID) {
                let record = APRSMessageRecord(
                    peer: envelope.source,
                    direction: .incoming,
                    text: text,
                    messageID: messageID,
                    status: .received
                )
                modelContext?.insert(record)
                try? modelContext?.save()
            }
            if let messageID {
                let packet = try? codec.encodePacket(
                    source: TNC2Address(callsign: identity.callsign, ssid: identity.ssid),
                    addressee: envelope.source,
                    payload: .acknowledgement(messageID)
                )
                if let packet { try? await client.send(packet: packet) }
            }
        case let .acknowledgement(messageID):
            updateOutgoing(peer: envelope.source, messageID: messageID, status: .acknowledged)
        case let .rejection(messageID):
            updateOutgoing(peer: envelope.source, messageID: messageID, status: .unconfirmed)
        }
    }

    private func updateOutgoing(
        peer: TNC2Address,
        messageID: APRSMessageID,
        status: APRSMessageDeliveryStatus
    ) {
        let callsign = peer.callsign
        let ssid = Int(peer.ssid)
        let rawID = messageID.rawValue
        let outgoing = APRSMessageDirection.outgoing.rawValue
        let descriptor = FetchDescriptor<APRSMessageRecord>(
            predicate: #Predicate {
                $0.peerCallsign == callsign
                    && $0.peerSSID == ssid
                    && $0.messageID == rawID
                    && $0.directionRawValue == outgoing
            },
            sortBy: [SortDescriptor(\APRSMessageRecord.createdAt, order: .reverse)]
        )
        guard let record = try? modelContext?.fetch(descriptor).first else { return }
        record.status = status
        pendingTasks.removeValue(forKey: record.id)?.cancel()
        try? modelContext?.save()
    }

    private func isDuplicate(peer: TNC2Address, messageID: APRSMessageID?) -> Bool {
        guard let messageID else { return false }
        let callsign = peer.callsign
        let ssid = Int(peer.ssid)
        let rawID = messageID.rawValue
        let incoming = APRSMessageDirection.incoming.rawValue
        let descriptor = FetchDescriptor<APRSMessageRecord>(
            predicate: #Predicate {
                $0.peerCallsign == callsign
                    && $0.peerSSID == ssid
                    && $0.messageID == rawID
                    && $0.directionRawValue == incoming
            }
        )
        return ((try? modelContext?.fetchCount(descriptor)) ?? 0) > 0
    }

    private func fetchRecord(id: UUID) -> APRSMessageRecord? {
        let descriptor = FetchDescriptor<APRSMessageRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext?.fetch(descriptor).first
    }

    private func markAllPendingUnconfirmed() {
        pendingTasks.values.forEach { $0.cancel() }
        pendingTasks.removeAll()
        guard let modelContext else { return }
        let waiting = APRSMessageDeliveryStatus.waitingAcknowledgement.rawValue
        let sending = APRSMessageDeliveryStatus.sending.rawValue
        let descriptor = FetchDescriptor<APRSMessageRecord>(
            predicate: #Predicate { $0.statusRawValue == waiting || $0.statusRawValue == sending }
        )
        guard let records = try? modelContext.fetch(descriptor) else { return }
        records.forEach { $0.status = .unconfirmed }
        try? modelContext.save()
    }

    private func makeMessageID() throws -> APRSMessageID {
        let value = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(5)
        return try APRSMessageID(String(value))
    }
}
