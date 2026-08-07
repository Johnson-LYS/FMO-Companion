import Foundation
import SwiftData

nonisolated enum APRSMessageDirection: String, Codable, Sendable {
    case incoming
    case outgoing
}

nonisolated enum APRSMessageDeliveryStatus: String, Codable, Sendable {
    case received
    case sending
    case waitingAcknowledgement
    case acknowledged
    case unconfirmed
}

@Model
final class APRSMessageRecord {
    @Attribute(.unique) var id: UUID
    var peerCallsign: String
    var peerSSID: Int
    var directionRawValue: String
    var text: String
    var messageID: String?
    var statusRawValue: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        peer: TNC2Address,
        direction: APRSMessageDirection,
        text: String,
        messageID: APRSMessageID?,
        status: APRSMessageDeliveryStatus,
        createdAt: Date = Date()
    ) {
        self.id = id
        peerCallsign = peer.callsign
        peerSSID = Int(peer.ssid)
        directionRawValue = direction.rawValue
        self.text = text
        self.messageID = messageID?.rawValue
        statusRawValue = status.rawValue
        self.createdAt = createdAt
    }

    var peer: TNC2Address {
        TNC2Address(callsign: peerCallsign, ssid: UInt8(clamping: peerSSID))
    }

    var direction: APRSMessageDirection {
        get { APRSMessageDirection(rawValue: directionRawValue) ?? .incoming }
        set { directionRawValue = newValue.rawValue }
    }

    var status: APRSMessageDeliveryStatus {
        get { APRSMessageDeliveryStatus(rawValue: statusRawValue) ?? .unconfirmed }
        set { statusRawValue = newValue.rawValue }
    }
}
