import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class QSOModel {
    enum Phase: Equatable {
        case noDevice
        case neverSynced
        case offline(lastSync: Date?)
        case syncing(completed: Int, total: Int?)
        case current(lastSync: Date)
        case partial(lastSync: Date?)
        case failed(lastSync: Date?)
    }

    nonisolated struct Policy: Sendable {
        var pageSize = 100
        var maximumRecords = 10_000
        var recentDetailCount = 20
        var visibleRefreshInterval: Duration = .seconds(60)
    }

    private let reader: any FmoQSOReading
    private let policy: Policy
    private var modelContext: ModelContext?
    private var endpoint: FmoDeviceEndpoint?
    private var isDeviceConnected = false
    private var isActive = true
    private var isVisible = false
    private var generation = 0
    private var syncTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    var phase: Phase = .noDevice
    var records: [QSOCachedRecord] = []
    var lastIssue: String?
    var loadingDetailIDs = Set<Int64>()
    var exportProgress: (completed: Int, total: Int)?

    init(reader: any FmoQSOReading, policy: Policy = Policy()) {
        self.reader = reader
        self.policy = policy
    }

    var deviceName: String? { endpoint?.displayName }
    var lastCompleteSyncAt: Date? {
        switch phase {
        case let .offline(date), let .partial(date), let .failed(date): date
        case let .current(date): date
        default: metadata()?.lastCompleteSyncAt
        }
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        reloadCache()
    }

    func setDevice(endpoint: FmoDeviceEndpoint?, isConnected: Bool) async {
        let changedDevice = self.endpoint?.id != endpoint?.id
        let becameConnected = !isDeviceConnected && isConnected
        self.endpoint = endpoint
        isDeviceConnected = isConnected

        if changedDevice {
            generation += 1
            let previousTask = syncTask
            previousTask?.cancel()
            await previousTask?.value
            syncTask = nil
            await reader.disconnect()
            reloadCache()
        }
        refreshIdlePhase()
        if isActive, isConnected, endpoint != nil, changedDevice || becameConnected {
            await synchronize()
        }
    }

    func setActive(_ active: Bool) async {
        guard isActive != active else { return }
        isActive = active
        if active {
            if isDeviceConnected { await synchronize() }
            updatePolling()
        } else {
            generation += 1
            let previousTask = syncTask
            previousTask?.cancel()
            await previousTask?.value
            syncTask = nil
            pollingTask?.cancel()
            pollingTask = nil
            await reader.disconnect()
            refreshIdlePhase()
        }
    }

    func setVisible(_ visible: Bool) async {
        guard isVisible != visible else { return }
        isVisible = visible
        if visible, isActive, isDeviceConnected {
            await synchronize()
        } else if !visible, syncTask == nil {
            await reader.disconnect()
        }
        updatePolling()
    }

    func refresh() async {
        guard endpoint != nil else {
            phase = .noDevice
            return
        }
        guard isDeviceConnected, isActive else {
            phase = .offline(lastSync: metadata()?.lastCompleteSyncAt)
            return
        }
        await synchronize()
    }

    func loadDetail(logID: Int64) async {
        if let syncTask { await syncTask.value }
        guard !loadingDetailIDs.contains(logID),
              records.first(where: { $0.logID == logID })?.hasDetail != true else { return }
        guard let endpoint, isDeviceConnected, isActive else { return }
        loadingDetailIDs.insert(logID)
        defer { loadingDetailIDs.remove(logID) }
        do {
            try await reader.connect(to: endpoint)
            let detail = try await reader.detail(logID: logID)
            try merge(detail: detail)
            reloadCache()
        } catch is CancellationError {
        } catch FmoDeviceError.operationCancelled {
        } catch {
            lastIssue = String(localized: "暂时无法读取这条 QSO")
        }
    }

    func makeADIF() async -> String? {
        guard !records.isEmpty else { return nil }
        let missingIDs = records.filter { !$0.hasDetail }.map(\.logID)
        if !missingIDs.isEmpty {
            exportProgress = (0, missingIDs.count)
            for (index, logID) in missingIDs.enumerated() {
                guard !Task.isCancelled else {
                    exportProgress = nil
                    return nil
                }
                await loadDetail(logID: logID)
                exportProgress = (index + 1, missingIDs.count)
            }
            exportProgress = nil
        }
        guard records.allSatisfy(\.hasDetail) else {
            lastIssue = String(localized: "QSO 详情暂时不可用，无法导出")
            return nil
        }
        return QSOADIFEncoder().encode(records)
    }

    private func synchronize() async {
        if let syncTask {
            await syncTask.value
            return
        }
        let currentGeneration = generation
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performSync(generation: currentGeneration)
        }
        syncTask = task
        await task.value
        if generation == currentGeneration {
            syncTask = nil
        }
    }

    private func performSync(generation expectedGeneration: Int) async {
        guard let endpoint, let modelContext, isActive, isDeviceConnected else {
            refreshIdlePhase()
            return
        }
        let deviceID = endpoint.id
        let syncID = UUID().uuidString
        let metadata = metadata(createIfNeeded: true)
        metadata?.lastAttemptAt = Date()
        try? modelContext.save()
        phase = .syncing(completed: 0, total: nil)
        lastIssue = nil

        var allIDs = Set<Int64>()
        var fullListSucceeded = false
        var receivedListPage = false
        var detailFailure = false
        do {
            var cachedByLogID = try cachedRecordsByLogID(deviceID: deviceID)
            try await reader.connect(to: endpoint)
            var pageNumber = 0
            var expectedTotal: Int?
            while true {
                try Task.checkCancellation()
                guard generation == expectedGeneration, self.endpoint?.id == deviceID else {
                    throw CancellationError()
                }
                let page = try await reader.list(page: pageNumber, pageSize: policy.pageSize)
                receivedListPage = true
                if let expectedTotal, expectedTotal != page.totalCount {
                    throw FmoDeviceError.protocolViolation
                }
                expectedTotal = page.totalCount
                guard page.totalCount <= policy.maximumRecords else {
                    throw FmoDeviceError.protocolViolation
                }
                for summary in page.summaries {
                    guard allIDs.insert(summary.logID).inserted else {
                        throw FmoDeviceError.protocolViolation
                    }
                    merge(
                        summary: summary,
                        syncID: syncID,
                        deviceID: deviceID,
                        cachedByLogID: &cachedByLogID
                    )
                }
                try modelContext.save()
                if pageNumber == 0 || pageNumber.isMultiple(of: 5) || allIDs.count >= page.totalCount {
                    reloadCache()
                }
                phase = .syncing(completed: allIDs.count, total: page.totalCount)

                if allIDs.count >= page.totalCount { break }
                guard !page.summaries.isEmpty else { throw FmoDeviceError.protocolViolation }
                pageNumber += 1
            }
            guard allIDs.count == expectedTotal else { throw FmoDeviceError.protocolViolation }
            fullListSucceeded = true

            reconcile(cachedByLogID: cachedByLogID, seenIDs: allIDs)
            let recent = records.prefix(policy.recentDetailCount).filter { !$0.hasDetail }
            for record in recent {
                do {
                    let detail = try await reader.detail(logID: record.logID)
                    try merge(detail: detail)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    detailFailure = true
                    break
                }
            }
            let completedAt = Date()
            metadata?.lastCompleteSyncAt = completedAt
            metadata?.recordCount = allIDs.count
            try modelContext.save()
            reloadCache()
            phase = detailFailure ? .partial(lastSync: completedAt) : .current(lastSync: completedAt)
        } catch is CancellationError {
            refreshIdlePhase()
        } catch FmoDeviceError.operationCancelled {
            if generation == expectedGeneration { refreshIdlePhase() }
        } catch {
            guard generation == expectedGeneration, self.endpoint?.id == deviceID else { return }
            reloadCache()
            let lastSync = metadata?.lastCompleteSyncAt
            phase = fullListSucceeded || receivedListPage
                ? .partial(lastSync: lastSync)
                : .failed(lastSync: lastSync)
            lastIssue = String(localized: "QSO 暂时无法更新，已保留上次内容")
        }
        await reader.disconnect()
    }

    private func merge(
        summary: FmoQSOSummary,
        syncID: String,
        deviceID: String,
        cachedByLogID: inout [Int64: FmoQSORecord]
    ) {
        guard let modelContext else { return }
        if let record = cachedByLogID[summary.logID] {
            record.merge(summary: summary, syncID: syncID)
        } else {
            let record = FmoQSORecord(deviceID: deviceID, summary: summary, syncID: syncID)
            modelContext.insert(record)
            cachedByLogID[summary.logID] = record
        }
    }

    private func merge(detail: FmoQSODetail) throws {
        guard let modelContext, let deviceID = endpoint?.id else { return }
        let key = FmoQSORecord.cacheKey(deviceID: deviceID, logID: detail.logID)
        let descriptor = FetchDescriptor<FmoQSORecord>(predicate: #Predicate { $0.cacheKey == key })
        guard let record = try modelContext.fetch(descriptor).first else {
            throw FmoDeviceError.protocolViolation
        }
        record.merge(detail: detail)
        try modelContext.save()
    }

    private func reconcile(cachedByLogID: [Int64: FmoQSORecord], seenIDs: Set<Int64>) {
        guard let modelContext else { return }
        for (logID, record) in cachedByLogID where !seenIDs.contains(logID) {
            modelContext.delete(record)
        }
    }

    private func cachedRecordsByLogID(deviceID: String) throws -> [Int64: FmoQSORecord] {
        guard let modelContext else { return [:] }
        let descriptor = FetchDescriptor<FmoQSORecord>(predicate: #Predicate { $0.deviceID == deviceID })
        return Dictionary(uniqueKeysWithValues: try modelContext.fetch(descriptor).map { ($0.logID, $0) })
    }

    private func reloadCache() {
        guard let modelContext, let deviceID = endpoint?.id else {
            records = []
            phase = .noDevice
            return
        }
        var descriptor = FetchDescriptor<FmoQSORecord>(
            predicate: #Predicate { $0.deviceID == deviceID },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = policy.maximumRecords
        records = (try? modelContext.fetch(descriptor).map(\.cachedValue)) ?? []
        refreshIdlePhase()
    }

    private func metadata(createIfNeeded: Bool = false) -> FmoQSOSyncMetadata? {
        guard let modelContext, let deviceID = endpoint?.id else { return nil }
        let descriptor = FetchDescriptor<FmoQSOSyncMetadata>(predicate: #Predicate { $0.deviceID == deviceID })
        if let existing = try? modelContext.fetch(descriptor).first { return existing }
        guard createIfNeeded else { return nil }
        let value = FmoQSOSyncMetadata(deviceID: deviceID)
        modelContext.insert(value)
        return value
    }

    private func refreshIdlePhase() {
        guard endpoint != nil else {
            phase = .noDevice
            return
        }
        guard isDeviceConnected, isActive else {
            phase = .offline(lastSync: metadata()?.lastCompleteSyncAt)
            return
        }
        if case .syncing = phase { return }
        if let lastSync = metadata()?.lastCompleteSyncAt {
            phase = .current(lastSync: lastSync)
        } else {
            phase = .neverSynced
        }
    }

    private func updatePolling() {
        pollingTask?.cancel()
        pollingTask = nil
        guard isVisible, isActive, isDeviceConnected else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: policy.visibleRefreshInterval) } catch { return }
                await self.refresh()
            }
        }
    }
}
