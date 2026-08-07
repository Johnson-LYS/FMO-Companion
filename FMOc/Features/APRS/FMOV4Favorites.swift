import Foundation
import SwiftData

@Model
final class FavoriteCallsign {
    @Attribute(.unique) var normalizedCallsign: String
    var displayCallsign: String
    var lastSSID: Int?
    var createdAt: Date

    init(callsign: String, ssid: UInt8? = nil, createdAt: Date = Date()) {
        let normalized = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        normalizedCallsign = normalized
        displayCallsign = normalized
        lastSSID = ssid.map(Int.init)
        self.createdAt = createdAt
    }
}

@Model
final class FavoriteServer {
    @Attribute(.unique) var uid: String
    var displayName: String
    var createdAt: Date

    init(uid: UInt64, displayName: String, createdAt: Date = Date()) {
        self.uid = String(uid)
        self.displayName = displayName
        self.createdAt = createdAt
    }

    var numericUID: UInt64? { UInt64(uid) }
}

nonisolated enum FMOV4FavoriteKey {
    static func callsign(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
