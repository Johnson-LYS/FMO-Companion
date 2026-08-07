import CryptoKit
import Foundation

nonisolated enum FMOV4NetworkEventKind: String, CaseIterable, Sendable {
    case cq
    case omcq
    case vocal
    case online
    case beacon
    case station
    case event
}

nonisolated struct FMOV4StationRecord: Identifiable, Equatable, Sendable {
    let id: String
    let callsign: String
    let ssid: UInt8
    let latitude: Double
    let longitude: Double
    let serverUID: UInt64?
    let frequency: String?
    let lastActivity: FMOV4NetworkEventKind?
    let observedAt: Date
    let certificateExpiresAt: Date
    let issuerSerialNumber: UInt64
    let trustLevel: FMOV4TrustLevel
    let rootCRL: FMOV4CRLFreshness
    let intermediateCRL: FMOV4CRLFreshness
}

nonisolated struct FMOV4ServerRecord: Identifiable, Equatable, Sendable {
    var id: UInt64 { uid }
    let uid: UInt64
    let name: String
    let countryCode: String
    let host: String
    let port: UInt16
    let filterKilometers: UInt32
    let onlineUserCount: UInt32
    let peakUserCount: UInt32
    let latitude: Double
    let longitude: Double
    let broadcasterCallsign: String
    let observedAt: Date
    let trustLevel: FMOV4TrustLevel
}

nonisolated struct FMOV4NetworkEvent: Identifiable, Equatable, Sendable {
    let id: String
    let kind: FMOV4NetworkEventKind
    let callsign: String
    let ssid: UInt8
    let latitude: Double
    let longitude: Double
    let serverUID: UInt64?
    let topic: String?
    let content: String?
    let observedAt: Date
    let trustLevel: FMOV4TrustLevel
}

nonisolated struct FMOV4NetworkSnapshot: Equatable, Sendable {
    var stations: [FMOV4StationRecord] = []
    var servers: [FMOV4ServerRecord] = []
    var events: [FMOV4NetworkEvent] = []
    var rejectedCounts: [FMOV4VerificationFailure: Int] = [:]

    static let empty = FMOV4NetworkSnapshot()
}

protocol FMOV4NetworkProcessing: Actor {
    func process(_ frame: UnverifiedFMOV4Frame, at date: Date) async -> FMOV4NetworkSnapshot
    func snapshot() -> FMOV4NetworkSnapshot
}

actor DiscardingFMOV4NetworkProcessor: FMOV4NetworkProcessing {
    func process(_ frame: UnverifiedFMOV4Frame, at date: Date) -> FMOV4NetworkSnapshot { .empty }
    func snapshot() -> FMOV4NetworkSnapshot { .empty }
}

actor FMOV4NetworkStore: FMOV4NetworkProcessing {
    nonisolated struct Policy: Sendable {
        var maximumEvents = 200
        var eventLifetime: TimeInterval = 24 * 60 * 60
        var maximumPendingJoints = 256
        var jointLifetime: TimeInterval = 20 * 60
        var maximumSeenMessages = 1_024
    }

    private struct PendingJoint: Sendable {
        let frame: AuthenticatedFMOV4PositionFrame
        let expiresAt: Date
    }

    private let verifier: FMOV4Verifier
    private let policy: Policy
    private var stations: [String: FMOV4StationRecord] = [:]
    private var servers: [UInt64: FMOV4ServerRecord] = [:]
    private var events: [FMOV4NetworkEvent] = []
    private var pendingJoints: [String: PendingJoint] = [:]
    private var seenMessages: Set<String> = []
    private var seenMessageOrder: [String] = []
    private var rejectedCounts: [FMOV4VerificationFailure: Int] = [:]

    init(verifier: FMOV4Verifier, policy: Policy = Policy()) {
        self.verifier = verifier
        self.policy = policy
    }

    func process(_ frame: UnverifiedFMOV4Frame, at date: Date) async -> FMOV4NetworkSnapshot {
        removeExpiredJoints(at: date)
        removeExpiredEvents(at: date)
        switch frame {
        case .position(let position):
            let result = await verifier.verify(position, at: date)
            switch result {
            case .rejected(let failure):
                rejectedCounts[failure, default: 0] += 1
            case .accepted(let authenticated):
                let messageID = Self.messageID(signature: position.signature)
                guard !seenMessages.contains(messageID) else { return makeSnapshot() }
                rememberMessage(messageID)
                reduce(authenticated, messageID: messageID)
            }
        case .event(let event):
            reduce(event, at: date)
        }
        return makeSnapshot()
    }

    func snapshot() -> FMOV4NetworkSnapshot {
        makeSnapshot()
    }

    private func reduce(
        _ frame: AuthenticatedFMOV4PositionFrame,
        messageID: String
    ) {
        let stationID = frame.source.formatted
        let previous = stations[stationID]
        var serverUID = previous?.serverUID
        var frequency = previous?.frequency
        var lastActivity = previous?.lastActivity

        switch frame.body {
        case .activity(let activity):
            serverUID = activity.serverUID
            let kind = Self.eventKind(activity.type)
            lastActivity = kind
            appendEvent(
                id: messageID,
                kind: kind,
                frame: frame,
                serverUID: activity.serverUID
            )
        case .beacon(let beacon):
            frequency = beacon.frequency
            lastActivity = .beacon
            appendEvent(id: messageID, kind: .beacon, frame: frame, serverUID: serverUID)
        case .station(let station):
            lastActivity = .station
            let uid = frame.certificate.uid
            servers[uid] = FMOV4ServerRecord(
                uid: uid,
                name: station.name,
                countryCode: station.countryCode,
                host: station.host,
                port: station.port,
                filterKilometers: station.filterKilometers,
                onlineUserCount: station.onlineUserCount,
                peakUserCount: station.peakUserCount,
                latitude: frame.latitude,
                longitude: frame.longitude,
                broadcasterCallsign: frame.source.formatted,
                observedAt: frame.verifiedAt,
                trustLevel: frame.trustLevel
            )
            appendEvent(id: messageID, kind: .station, frame: frame, serverUID: uid)
        case .joint(let statusHash):
            let key = Self.jointKey(source: frame.source, hash: statusHash)
            pendingJoints[key] = PendingJoint(
                frame: frame,
                expiresAt: frame.verifiedAt.addingTimeInterval(policy.jointLifetime)
            )
            trimPendingJoints()
        }

        stations[stationID] = FMOV4StationRecord(
            id: stationID,
            callsign: frame.source.callsign,
            ssid: frame.source.ssid,
            latitude: frame.latitude,
            longitude: frame.longitude,
            serverUID: serverUID,
            frequency: frequency,
            lastActivity: lastActivity,
            observedAt: frame.verifiedAt,
            certificateExpiresAt: Date(timeIntervalSince1970: TimeInterval(frame.certificate.expiresAt)),
            issuerSerialNumber: frame.certificate.issuerSerialNumber,
            trustLevel: frame.trustLevel,
            rootCRL: frame.rootCRL,
            intermediateCRL: frame.intermediateCRL
        )
    }

    private func reduce(_ event: UnverifiedFMOV4EventFrame, at date: Date) {
        let hash = Data(SHA256.hash(data: Data(event.rawStatusPayload.utf8)))
        let key = Self.jointKey(source: event.source, hash: hash)
        guard
            let pending = pendingJoints.removeValue(forKey: key),
            pending.expiresAt >= date,
            pending.frame.source == event.source,
            pending.frame.certificate.uid == event.uid
        else {
            return
        }
        let eventID = Self.messageID(signature: hash)
        guard !seenMessages.contains(eventID) else { return }
        rememberMessage(eventID)
        appendEvent(
            FMOV4NetworkEvent(
                id: eventID,
                kind: .event,
                callsign: event.source.callsign,
                ssid: event.source.ssid,
                latitude: pending.frame.latitude,
                longitude: pending.frame.longitude,
                serverUID: nil,
                topic: event.topic,
                content: event.content,
                observedAt: date,
                trustLevel: pending.frame.trustLevel
            )
        )
    }

    private func appendEvent(
        id: String,
        kind: FMOV4NetworkEventKind,
        frame: AuthenticatedFMOV4PositionFrame,
        serverUID: UInt64?
    ) {
        appendEvent(
            FMOV4NetworkEvent(
                id: id,
                kind: kind,
                callsign: frame.source.callsign,
                ssid: frame.source.ssid,
                latitude: frame.latitude,
                longitude: frame.longitude,
                serverUID: serverUID,
                topic: nil,
                content: nil,
                observedAt: frame.verifiedAt,
                trustLevel: frame.trustLevel
            )
        )
    }

    private func appendEvent(_ event: FMOV4NetworkEvent) {
        events.insert(event, at: 0)
        events = Self.retainedEvents(events, at: event.observedAt, policy: policy)
    }

    private func makeSnapshot() -> FMOV4NetworkSnapshot {
        FMOV4NetworkSnapshot(
            stations: stations.values.sorted { $0.observedAt > $1.observedAt },
            servers: servers.values.sorted { $0.observedAt > $1.observedAt },
            events: events,
            rejectedCounts: rejectedCounts
        )
    }

    private func rememberMessage(_ id: String) {
        seenMessages.insert(id)
        seenMessageOrder.append(id)
        if seenMessageOrder.count > policy.maximumSeenMessages {
            let overflow = seenMessageOrder.count - policy.maximumSeenMessages
            let removed = Array(seenMessageOrder.prefix(overflow))
            seenMessageOrder.removeFirst(overflow)
            for id in removed { seenMessages.remove(id) }
        }
    }

    private func removeExpiredJoints(at date: Date) {
        pendingJoints = pendingJoints.filter { $0.value.expiresAt >= date }
    }

    private func removeExpiredEvents(at date: Date) {
        events = Self.retainedEvents(events, at: date, policy: policy)
    }

    nonisolated static func retainedEvents(
        _ events: [FMOV4NetworkEvent],
        at date: Date,
        policy: Policy
    ) -> [FMOV4NetworkEvent] {
        let cutoff = date.addingTimeInterval(-policy.eventLifetime)
        return Array(events.filter { $0.observedAt >= cutoff }.prefix(policy.maximumEvents))
    }

    private func trimPendingJoints() {
        guard pendingJoints.count > policy.maximumPendingJoints else { return }
        let overflow = pendingJoints.count - policy.maximumPendingJoints
        for key in pendingJoints.sorted(by: { $0.value.expiresAt < $1.value.expiresAt }).prefix(overflow).map(\.key) {
            pendingJoints.removeValue(forKey: key)
        }
    }

    private static func eventKind(_ type: FMOV4ActivityType) -> FMOV4NetworkEventKind {
        switch type {
        case .cq: .cq
        case .omcq: .omcq
        case .vocal: .vocal
        case .online: .online
        }
    }

    private static func messageID(signature: Data) -> String {
        FMOV4Base64URL.encode(Data(SHA256.hash(data: signature)))
    }

    private static func jointKey(source: TNC2Address, hash: Data) -> String {
        "\(source.formatted):\(FMOV4Base64URL.encode(hash))"
    }
}
