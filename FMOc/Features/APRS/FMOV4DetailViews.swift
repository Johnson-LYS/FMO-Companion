import MapKit
import SwiftData
import SwiftUI

struct FMOV4StationDetailView: View {
    let station: FMOV4StationRecord
    @Environment(\.modelContext) private var modelContext
    @Query private var favorites: [FavoriteCallsign]

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: station.lastActivity?.symbol ?? "person.wave.2")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.12), in: .circle)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(station.id)
                            .font(.title3.bold().monospaced())
                        if let activity = station.lastActivity {
                            Text(activity.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button { toggleFavorite() } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? Color.accentColor : .secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("位置与状态") {
                LabeledContent("坐标") {
                    Text("\(station.latitude, format: .number.precision(.fractionLength(4))), \(station.longitude, format: .number.precision(.fractionLength(4)))")
                        .monospacedDigit()
                }
                if let frequency = station.frequency {
                    LabeledContent("频率", value: frequency)
                }
                if let activity = station.lastActivity {
                    LabeledContent("最近活动", value: String(localized: activity.title))
                }
                LabeledContent("收到时间") {
                    Text(station.observedAt, style: .relative)
                }
            }
        }
        .navigationTitle("台站详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isFavorite: Bool {
        favorites.contains { $0.normalizedCallsign == FMOV4FavoriteKey.callsign(station.callsign) }
    }

    private func toggleFavorite() {
        if let favorite = favorites.first(where: {
            $0.normalizedCallsign == FMOV4FavoriteKey.callsign(station.callsign)
        }) {
            modelContext.delete(favorite)
        } else {
            modelContext.insert(FavoriteCallsign(callsign: station.callsign, ssid: station.ssid))
        }
        try? modelContext.save()
    }
}

struct FMOV4ServerDetailView: View {
    let server: FMOV4ServerRecord
    @Environment(\.modelContext) private var modelContext
    @Query private var favorites: [FavoriteServer]

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "server.rack")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.12), in: .circle)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.name).font(.title3.bold())
                        Text("\(server.onlineUserCount) 在线")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { toggleFavorite() } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? Color.accentColor : .secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("服务信息") {
                LabeledContent("在线", value: "\(server.onlineUserCount)")
                LabeledContent("峰值", value: "\(server.peakUserCount)")
                LabeledContent("覆盖", value: "\(server.filterKilometers) km")
                LabeledContent("地址", value: "\(server.host):\(server.port)")
                LabeledContent("广播台站", value: server.broadcasterCallsign)
                LabeledContent("国家/地区", value: server.countryCode)
                LabeledContent("最近收到") { Text(server.observedAt, style: .relative) }
            }
        }
        .navigationTitle("服务器详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isFavorite: Bool { favorites.contains { $0.numericUID == server.uid } }

    private func toggleFavorite() {
        if let favorite = favorites.first(where: { $0.numericUID == server.uid }) {
            modelContext.delete(favorite)
        } else {
            modelContext.insert(FavoriteServer(uid: server.uid, displayName: server.name))
        }
        try? modelContext.save()
    }
}

struct FMOV4EventExplorerView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case cq
        case omcq
        case vocal
        case online
        case beacon
        case station
        case event
        case favorites

        var id: Self { self }
        var title: String {
            switch self {
            case .all: String(localized: "全部")
            case .cq: "CQ"
            case .omcq: "OMCQ"
            case .vocal: "VOCAL"
            case .online: "ONLINE"
            case .beacon: "BEACON"
            case .station: "STATION"
            case .event: "EVENT"
            case .favorites: String(localized: "收藏")
            }
        }
    }

    let snapshot: FMOV4NetworkSnapshot
    @State private var filter = Filter.all
    @State private var searchText = ""
    @Query private var favoriteCallsigns: [FavoriteCallsign]
    @Query private var favoriteServers: [FavoriteServer]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Filter.allCases) { item in
                        Button(item.title) { filter = item }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(filter == item ? .black : .primary)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 36)
                            .background(
                                filter == item ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground),
                                in: .capsule
                            )
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)

            Label("仅保留最近 24 小时 · 最多 200 条", systemImage: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if filteredEvents.isEmpty {
                ContentUnavailableView {
                    Label("暂无匹配动态", systemImage: filter == .favorites ? "star" : "waveform.path.ecg")
                } description: {
                    Text(filter == .favorites ? "可先在台站与服务器目录中添加收藏。" : "收到网络数据后会自动更新。")
                }
            } else {
                List(filteredEvents) { event in
                    FMOV4EventRow(event: event)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("完整事件流")
        .searchable(text: $searchText, prompt: "搜索呼号或事件")
    }

    private var filteredEvents: [FMOV4NetworkEvent] {
        let favoriteCallsignSet = Set(favoriteCallsigns.map(\.normalizedCallsign))
        let favoriteServerSet = Set(favoriteServers.compactMap(\.numericUID))
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.events.filter { event in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .cq: matchesFilter = event.kind == .cq
            case .omcq: matchesFilter = event.kind == .omcq
            case .vocal: matchesFilter = event.kind == .vocal
            case .online: matchesFilter = event.kind == .online
            case .beacon: matchesFilter = event.kind == .beacon
            case .station: matchesFilter = event.kind == .station
            case .event: matchesFilter = event.kind == .event
            case .favorites:
                matchesFilter = favoriteCallsignSet.contains(FMOV4FavoriteKey.callsign(event.callsign))
                    || event.serverUID.map(favoriteServerSet.contains) == true
            }
            guard matchesFilter else { return false }
            guard !search.isEmpty else { return true }
            return event.callsign.localizedCaseInsensitiveContains(search)
                || event.topic?.localizedCaseInsensitiveContains(search) == true
                || event.content?.localizedCaseInsensitiveContains(search) == true
        }
    }
}
