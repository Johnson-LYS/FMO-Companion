import ActivityKit
import Foundation

nonisolated struct FmoDashboardActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        nonisolated enum Connection: String, Codable, Hashable, Sendable {
            case connected
            case stale
            case disconnected
        }

        nonisolated struct ActivityItem: Codable, Hashable, Sendable {
            nonisolated enum Kind: String, Codable, Hashable, Sendable {
                case speaking
                case recent
            }

            let kind: Kind
            let callsign: String
            let grid: String?
            let occurredAt: Date?
        }

        let connection: Connection
        let callsign: String?
        let serverName: String?
        let maidenhead: String?
        let activity: ActivityItem?
        let updatedAt: Date
    }

    let schemaVersion: Int

    init(schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion
    }
}
