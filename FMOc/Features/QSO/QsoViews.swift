import MapKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct QsoHomeView: View {
    @Bindable var model: QSOModel
    @State private var exportDocument: ADIFDocument?
    @State private var isExporting = false
    @State private var exportIssue: String?

    var body: some View {
        Group {
            if model.deviceName == nil {
                ContentUnavailableView {
                    Label("尚未连接 FMO", systemImage: "antenna.radiowaves.left.and.right.slash")
                } description: {
                    Text("在“设备”中连接 FMO 后，QSO 会自动出现在这里。")
                }
            } else if model.records.isEmpty, !isSynchronizing {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: emptySymbol)
                } description: {
                    Text(emptyDescription)
                } actions: {
                    if model.deviceName != nil {
                        Button("刷新") { Task { await model.refresh() } }
                            .buttonStyle(.borderedProminent)
                            .tint(.accentColor)
                            .foregroundStyle(.black)
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        syncCard
                        summaryCard
                        recentSection
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .refreshable { await model.refresh() }
            }
        }
        .navigationTitle("QSO")
        .toolbar {
            if !model.records.isEmpty {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        QsoBrowserView(model: model)
                    } label: {
                        Label("搜索", systemImage: "magnifyingglass")
                    }
                    Button {
                        Task {
                            if let adif = await model.makeADIF() {
                                exportDocument = ADIFDocument(text: adif)
                                isExporting = true
                            } else {
                                exportIssue = model.lastIssue ?? String(localized: "暂时无法生成 ADIF")
                            }
                        }
                    } label: {
                        if model.exportProgress == nil {
                            Label("导出 ADIF", systemImage: "square.and.arrow.up")
                        } else {
                            ProgressView()
                        }
                    }
                    .disabled(model.exportProgress != nil)
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .data,
            defaultFilename: "FMO-QSO.adi"
        ) { _ in
            exportDocument = nil
        }
        .alert(
            "无法导出 ADIF",
            isPresented: Binding(
                get: { exportIssue != nil },
                set: { if !$0 { exportIssue = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { exportIssue = nil }
        } message: {
            Text(exportIssue ?? "")
        }
        .task { await model.setVisible(true) }
        .onDisappear { Task { await model.setVisible(false) } }
    }

    private var syncCard: some View {
        Button { Task { await model.refresh() } } label: {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.deviceName ?? "FMO")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(syncStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSynchronizing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 36)
                        .background(.quaternary, in: .circle)
                }
            }
            .padding(12)
            .contentShape(.rect)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.separator.opacity(0.35), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(isSynchronizing)
        .accessibilityHint("刷新当前设备的 QSO")
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本机 QSO")
                .font(.caption.weight(.semibold))
            Text(model.records.count, format: .number)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
            HStack(spacing: 16) {
                Label("本月 \(currentMonthCount)", systemImage: "calendar")
                if let latest = model.records.first?.timestamp {
                    Label { Text(latest, style: .relative) } icon: { Image(systemName: "clock") }
                }
            }
            .font(.caption)
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(colors: [.accentColor, Color(red: 1, green: 0.68, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 22)
        )
        .accessibilityElement(children: .combine)
    }

    private var recentSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("最近通联").font(.title3.bold())
                Spacer()
                NavigationLink("全部") { QsoBrowserView(model: model) }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 10)

            VStack(spacing: 0) {
                ForEach(Array(model.records.prefix(6).enumerated()), id: \.element.id) { index, record in
                    NavigationLink {
                        QsoDetailView(model: model, logID: record.logID)
                    } label: {
                        QsoRow(record: record)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if index < min(model.records.count, 6) - 1 { Divider().padding(.leading, 52) }
                }
            }
            .padding(.horizontal, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        }
    }

    private var currentMonthCount: Int {
        let calendar = Calendar.current
        return model.records.count { calendar.isDate($0.timestamp, equalTo: Date(), toGranularity: .month) }
    }

    private var isSynchronizing: Bool {
        if case .syncing = model.phase { true } else { false }
    }

    private var syncStatusText: String {
        switch model.phase {
        case .noDevice: String(localized: "等待设备")
        case .neverSynced: String(localized: "尚未同步")
        case let .offline(lastSync):
            lastSync.map { String(localized: "离线 · \($0.formatted(.relative(presentation: .named)))") }
                ?? String(localized: "设备离线")
        case let .syncing(completed, total):
            total.map { String(localized: "正在同步 \(completed)/\($0)") }
                ?? String(localized: "正在同步")
        case let .current(lastSync):
            String(localized: "已同步 · \(lastSync.formatted(.relative(presentation: .named)))")
        case .partial: String(localized: "部分内容已更新")
        case .failed: String(localized: "更新失败 · 显示上次内容")
        }
    }

    private var emptyTitle: String {
        switch model.phase {
        case .offline: String(localized: "设备当前离线")
        case .failed: String(localized: "暂时无法同步")
        default: String(localized: "暂无 QSO")
        }
    }

    private var emptySymbol: String {
        switch model.phase {
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        default: "book.closed"
        }
    }

    private var emptyDescription: String {
        switch model.phase {
        case .offline: String(localized: "重新连接这台 FMO 后会自动同步。")
        case .failed: String(localized: "请确认 FMO 在线并在同一局域网。")
        default: String(localized: "这台 FMO 还没有通联记录。")
        }
    }
}

struct QsoBrowserView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all
        case recent
        case withGrid

        var id: Self { self }
        var title: String {
            switch self {
            case .all: String(localized: "全部")
            case .recent: String(localized: "最近 30 天")
            case .withGrid: String(localized: "有网格")
            }
        }
    }

    @Bindable var model: QSOModel
    @State private var query = ""
    @State private var filter = Filter.all

    var body: some View {
        Group {
            if filteredRecords.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(filteredRecords) { record in
                    NavigationLink {
                        QsoDetailView(model: model, logID: record.logID)
                    } label: {
                        QsoRow(record: record)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("全部 QSO")
        .searchable(text: $query, prompt: "呼号、网格或服务器")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("筛选", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label(filter.title, systemImage: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityIdentifier("qso-filter-menu")
            }
        }
    }

    private var filteredRecords: [QSOCachedRecord] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.records.filter { record in
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .recent:
                matchesFilter = record.timestamp >= Date().addingTimeInterval(-30 * 86_400)
            case .withGrid:
                matchesFilter = record.fromGrid != nil || record.toGrid != nil
            }
            guard matchesFilter else { return false }
            guard !value.isEmpty else { return true }
            return [record.fromCallsign, record.toCallsign, record.fromGrid, record.toGrid, record.relayName, record.relayAdmin, record.mode]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(value) }
        }
    }
}

private struct QsoRow: View {
    let record: QSOCachedRecord

    var body: some View {
        HStack(spacing: 12) {
            Text(String(record.displayCallsign.prefix(2)))
                .font(.caption2.bold().monospaced())
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(record.displayCallsign).font(.headline.monospaced())
                HStack(spacing: 5) {
                    if let grid = record.displayGrid { Text(grid) }
                    if let relay = record.relayName { Text("· \(relay)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            Text(record.timestamp, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

struct QsoDetailView: View {
    @Bindable var model: QSOModel
    let logID: Int64

    var body: some View {
        Group {
            if let record {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.toCallsign)
                                .font(.title2.bold().monospaced())
                            Text(record.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }

                    if hasMap(record) {
                        Section("网格") { QsoGridMap(record: record).frame(height: 220) }
                    }

                    Section("通联") {
                        if let value = record.fromCallsign { LabeledContent("本机", value: value) }
                        LabeledContent("对方", value: record.toCallsign)
                        if let value = record.fromGrid { LabeledContent("本机网格", value: value) }
                        if let value = record.toGrid { LabeledContent("对方网格", value: value) }
                        if let value = record.mode { LabeledContent("模式", value: value) }
                        if let value = record.frequencyRaw {
                            LabeledContent("频率", value: frequencyText(value))
                        }
                    }

                    if record.relayName != nil || record.relayAdmin != nil {
                        Section("服务器") {
                            if let value = record.relayName {
                                LabeledContent("名称") {
                                    Text(value)
                                        .accessibilityIdentifier("qso-relay-name")
                                }
                            }
                            if let value = record.relayAdmin { LabeledContent("管理员", value: value) }
                        }
                    }
                    if let comment = record.comment {
                        Section("备注") { Text(comment) }
                    }
                }
                .overlay {
                    if !record.hasDetail, model.loadingDetailIDs.contains(logID) {
                        ProgressView("正在读取详情")
                            .padding()
                            .background(.regularMaterial, in: .rect(cornerRadius: 14))
                    }
                }
            } else {
                ContentUnavailableView("QSO 不存在", systemImage: "book.closed")
            }
        }
        .navigationTitle("QSO 详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadDetail(logID: logID) }
    }

    private var record: QSOCachedRecord? { model.records.first { $0.logID == logID } }

    private func hasMap(_ record: QSOCachedRecord) -> Bool {
        [record.fromGrid, record.toGrid].compactMap { $0 }.contains { MaidenheadGrid.center(of: $0) != nil }
    }

    private func frequencyText(_ rawValue: Int64) -> String {
        let value = Double(rawValue) / 10_000
        return "\(value.formatted(.number.precision(.fractionLength(4)))) MHz"
    }
}

private struct QsoGridMap: View {
    let record: QSOCachedRecord
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            if let grid = record.fromGrid, let coordinate = MaidenheadGrid.center(of: grid) {
                Marker("本机 · \(grid)", systemImage: "antenna.radiowaves.left.and.right", coordinate: coordinate.clLocationCoordinate)
                    .tint(.orange)
            }
            if let grid = record.toGrid, let coordinate = MaidenheadGrid.center(of: grid) {
                Marker("对方 · \(grid)", systemImage: "person.wave.2", coordinate: coordinate.clLocationCoordinate)
                    .tint(.green)
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .clipShape(.rect(cornerRadius: 14))
        .overlay(alignment: .bottomLeading) {
            Text("网格中心仅表示大致区域")
                .font(.caption2)
                .padding(7)
                .background(.regularMaterial, in: .capsule)
                .padding(8)
        }
    }
}

private extension GeoCoordinate {
    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ADIFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
