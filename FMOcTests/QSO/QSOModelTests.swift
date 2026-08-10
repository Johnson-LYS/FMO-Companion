import Foundation
import SwiftData
import Testing
@testable import FMOc

@MainActor
struct QSOModelTests {
    @Test
    func syncsAllPagesLoadsRecentDetailsAndKeepsDevicesIsolated() async throws {
        let reader = QSOModelReader()
        let deviceA = try FmoDeviceEndpoint(host: "192.0.2.10", source: .manual, name: "FMO A")
        let deviceB = try FmoDeviceEndpoint(host: "192.0.2.11", source: .manual, name: "FMO B")
        await reader.set(records: [fixture(1), fixture(2)], for: deviceA.id)
        await reader.set(records: [fixture(9)], for: deviceB.id)
        let (model, container) = try makeModel(reader: reader, pageSize: 1)
        _ = container

        await model.setDevice(endpoint: deviceA, isConnected: true)
        #expect(model.records.map(\.logID) == [2, 1])
        #expect(model.records.allSatisfy { $0.hasDetail })
        guard case .current = model.phase else { Issue.record("Expected current state"); return }

        await model.setDevice(endpoint: deviceB, isConnected: true)
        #expect(model.records.map(\.logID) == [9])

        await model.setDevice(endpoint: deviceA, isConnected: false)
        #expect(model.records.map(\.logID) == [2, 1])
        guard case .offline(let date) = model.phase else { Issue.record("Expected offline cache"); return }
        #expect(date != nil)
    }

    @Test
    func partialPageFailureMergesNewDataWithoutDeletingCachedRecords() async throws {
        let reader = QSOModelReader()
        let endpoint = try FmoDeviceEndpoint(host: "192.0.2.20", source: .manual)
        await reader.set(records: [fixture(1), fixture(2)], for: endpoint.id)
        let (model, container) = try makeModel(reader: reader, pageSize: 1)
        _ = container
        await model.setDevice(endpoint: endpoint, isConnected: true)

        await reader.set(records: [fixture(3), fixture(4)], for: endpoint.id)
        await reader.setFailurePage(1)
        await model.refresh()

        #expect(Set(model.records.map(\.logID)).isSuperset(of: [1, 2, 4]))
        guard case .partial = model.phase else { Issue.record("Expected partial state with cache"); return }
    }

    @Test
    func syncsTenThousandSummariesWithinTheConfiguredBound() async throws {
        let reader = QSOModelReader()
        let endpoint = try FmoDeviceEndpoint(host: "192.0.2.40", source: .manual)
        let fixtures = (1...10_000).map { fixture(Int64($0)) }
        await reader.set(records: fixtures, for: endpoint.id)
        let (model, container) = try makeModel(reader: reader, pageSize: 100, recentDetailCount: 0)
        _ = container

        await model.setDevice(endpoint: endpoint, isConnected: true)

        #expect(model.records.count == 10_000)
        guard case .current = model.phase else { Issue.record("Expected current state"); return }
    }

    @Test
    func completeSyncReconcilesRemovedRecordsAndSummaryReuseClearsStaleDetail() async throws {
        let reader = QSOModelReader()
        let endpoint = try FmoDeviceEndpoint(host: "192.0.2.30", source: .manual)
        await reader.set(records: [fixture(1), fixture(2)], for: endpoint.id)
        let (model, container) = try makeModel(reader: reader, pageSize: 2)
        _ = container
        await model.setDevice(endpoint: endpoint, isConnected: true)

        let reused = fixture(2, callsign: "BG0NEW", timestamp: 1_800_001_000)
        await reader.set(records: [reused], for: endpoint.id)
        await model.refresh()
        #expect(model.records.map(\.logID) == [2])
        #expect(model.records.first?.toCallsign == "BG0NEW")
        #expect(model.records.first?.hasDetail == true)
    }

    @Test
    func refusesPartialADIFWhenAnyRequiredDetailCannotBeLoaded() async throws {
        let reader = QSOModelReader()
        let endpoint = try FmoDeviceEndpoint(host: "192.0.2.50", source: .manual)
        await reader.set(records: [fixture(1)], for: endpoint.id)
        await reader.setFailureDetailIDs([1])
        let (model, container) = try makeModel(reader: reader, pageSize: 100)
        _ = container

        await model.setDevice(endpoint: endpoint, isConnected: true)

        #expect(model.records.first?.hasDetail == false)
        #expect(await model.makeADIF() == nil)
        #expect(model.lastIssue == "QSO 详情暂时不可用，无法导出")
    }

    private func makeModel(
        reader: QSOModelReader,
        pageSize: Int,
        recentDetailCount: Int = 20
    ) throws -> (QSOModel, ModelContainer) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: FmoQSORecord.self,
            FmoQSOSyncMetadata.self,
            configurations: configuration
        )
        let model = QSOModel(
            reader: reader,
            policy: .init(
                pageSize: pageSize,
                maximumRecords: 10_000,
                recentDetailCount: recentDetailCount,
                visibleRefreshInterval: .seconds(600)
            )
        )
        model.configure(modelContext: container.mainContext)
        return (model, container)
    }

    private func fixture(
        _ id: Int64,
        callsign: String? = nil,
        timestamp: TimeInterval? = nil
    ) -> FmoQSODetail {
        FmoQSODetail(
            logID: id,
            timestamp: Date(timeIntervalSince1970: timestamp ?? 1_800_000_000 + Double(id)),
            fromCallsign: "BG0OWN",
            toCallsign: callsign ?? "BG0T\(id)",
            fromGrid: "OM89AA",
            toGrid: "PM01AB",
            frequencyRaw: 1_458_000,
            mode: "FM",
            relayName: "示例中继",
            relayAdmin: "BG0ADM",
            comment: "73"
        )
    }
}

private actor QSOModelReader: FmoQSOReading {
    private var recordsByDevice: [String: [FmoQSODetail]] = [:]
    private var currentDeviceID: String?
    private var failurePage: Int?
    private var failureDetailIDs = Set<Int64>()

    func set(records: [FmoQSODetail], for deviceID: String) {
        recordsByDevice[deviceID] = records.sorted { $0.timestamp > $1.timestamp }
        failurePage = nil
    }

    func setFailurePage(_ page: Int?) { failurePage = page }
    func setFailureDetailIDs(_ ids: Set<Int64>) { failureDetailIDs = ids }
    func connect(to endpoint: FmoDeviceEndpoint) { currentDeviceID = endpoint.id }

    func list(page: Int, pageSize: Int) throws -> FmoQSOListPage {
        if failurePage == page { throw FmoDeviceError.disconnected }
        guard let currentDeviceID else { throw FmoDeviceError.disconnected }
        let records = recordsByDevice[currentDeviceID] ?? []
        let start = min(page * pageSize, records.count)
        let end = min(start + pageSize, records.count)
        return FmoQSOListPage(
            totalCount: records.count,
            page: page,
            pageSize: pageSize,
            summaries: records[start..<end].map {
                FmoQSOSummary(logID: $0.logID, timestamp: $0.timestamp, toCallsign: $0.toCallsign, toGrid: $0.toGrid)
            }
        )
    }

    func detail(logID: Int64) throws -> FmoQSODetail {
        if failureDetailIDs.contains(logID) { throw FmoDeviceError.disconnected }
        guard let currentDeviceID,
              let detail = recordsByDevice[currentDeviceID]?.first(where: { $0.logID == logID }) else {
            throw FmoDeviceError.protocolViolation
        }
        return detail
    }

    func disconnect() { currentDeviceID = nil }
}
