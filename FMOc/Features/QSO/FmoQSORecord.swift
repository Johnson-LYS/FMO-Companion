import Foundation
import SwiftData

@Model
final class FmoQSORecord {
    @Attribute(.unique) var cacheKey: String
    var deviceID: String
    var logID: Int64
    var timestamp: Date
    var toCallsign: String
    var toGrid: String?
    var summaryFingerprint: String
    var lastSeenSyncID: String
    var fromCallsign: String?
    var fromGrid: String?
    var frequencyRaw: Int64?
    var mode: String?
    var relayName: String?
    var relayAdmin: String?
    var comment: String?
    var hasDetail: Bool

    init(deviceID: String, summary: FmoQSOSummary, syncID: String) {
        cacheKey = Self.cacheKey(deviceID: deviceID, logID: summary.logID)
        self.deviceID = deviceID
        logID = summary.logID
        timestamp = summary.timestamp
        toCallsign = summary.toCallsign
        toGrid = summary.toGrid
        summaryFingerprint = summary.fingerprint
        lastSeenSyncID = syncID
        hasDetail = false
    }

    func merge(summary: FmoQSOSummary, syncID: String) {
        if summaryFingerprint != summary.fingerprint {
            hasDetail = false
            fromCallsign = nil
            fromGrid = nil
            frequencyRaw = nil
            mode = nil
            relayName = nil
            relayAdmin = nil
            comment = nil
        }
        timestamp = summary.timestamp
        toCallsign = summary.toCallsign
        toGrid = summary.toGrid
        summaryFingerprint = summary.fingerprint
        lastSeenSyncID = syncID
    }

    func merge(detail: FmoQSODetail) {
        timestamp = detail.timestamp
        fromCallsign = detail.fromCallsign
        toCallsign = detail.toCallsign
        fromGrid = detail.fromGrid
        toGrid = detail.toGrid
        frequencyRaw = detail.frequencyRaw
        mode = detail.mode
        relayName = detail.relayName
        relayAdmin = detail.relayAdmin
        comment = detail.comment
        hasDetail = true
    }

    static func cacheKey(deviceID: String, logID: Int64) -> String {
        "\(deviceID)#\(logID)"
    }
}
@Model
final class FmoQSOSyncMetadata {
    @Attribute(.unique) var deviceID: String
    var lastCompleteSyncAt: Date?
    var lastAttemptAt: Date?
    var recordCount: Int

    init(deviceID: String) {
        self.deviceID = deviceID
        recordCount = 0
    }
}

nonisolated struct QSOCachedRecord: Identifiable, Equatable, Sendable {
    let deviceID: String
    let logID: Int64
    let timestamp: Date
    let fromCallsign: String?
    let toCallsign: String
    let fromGrid: String?
    let toGrid: String?
    let frequencyRaw: Int64?
    let mode: String?
    let relayName: String?
    let relayAdmin: String?
    let comment: String?
    let hasDetail: Bool

    var id: String { FmoQSORecord.cacheKey(deviceID: deviceID, logID: logID) }
    var displayCallsign: String { toCallsign }
    var displayGrid: String? { toGrid }
}

extension FmoQSORecord {
    var cachedValue: QSOCachedRecord {
        QSOCachedRecord(
            deviceID: deviceID,
            logID: logID,
            timestamp: timestamp,
            fromCallsign: fromCallsign,
            toCallsign: toCallsign,
            fromGrid: fromGrid,
            toGrid: toGrid,
            frequencyRaw: frequencyRaw,
            mode: mode,
            relayName: relayName,
            relayAdmin: relayAdmin,
            comment: comment,
            hasDetail: hasDetail
        )
    }
}
