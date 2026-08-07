import SwiftData
import SwiftUI

struct FMOV4StationDirectoryView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case stations
        case servers
        case favorites

        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .stations: "台站"
            case .servers: "服务器"
            case .favorites: "收藏"
            }
        }
    }

    let snapshot: FMOV4NetworkSnapshot
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteCallsign.createdAt) private var favoriteCallsigns: [FavoriteCallsign]
    @Query(sort: \FavoriteServer.createdAt) private var favoriteServers: [FavoriteServer]
    @State private var segment = Segment.stations
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                Picker("目录", selection: $segment) {
                    ForEach(Segment.allCases) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            switch segment {
            case .stations:
                stationSection(filteredStations)
            case .servers:
                serverSection(filteredServers)
            case .favorites:
                favoritesSections
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("台站与服务器")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索呼号或服务器"
        )
        .overlay {
            if visibleCount == 0 {
                ContentUnavailableView.search(text: searchText)
                    .offset(y: 70)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func stationSection(_ stations: [FMOV4StationRecord]) -> some View {
        Section("台站 · \(stations.count)") {
            ForEach(stations) { station in
                HStack(spacing: 10) {
                    NavigationLink {
                        FMOV4StationDetailView(station: station)
                    } label: {
                        stationLabel(station)
                    }
                    Button {
                        toggleFavorite(station)
                    } label: {
                        Image(systemName: isFavorite(station) ? "star.fill" : "star")
                            .foregroundStyle(isFavorite(station) ? Color.accentColor : .secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFavorite(station) ? "取消收藏 \(station.callsign)" : "收藏 \(station.callsign)")
                }
            }
        }
    }

    @ViewBuilder
    private func serverSection(_ servers: [FMOV4ServerRecord]) -> some View {
        Section("服务器 · \(servers.count)") {
            ForEach(servers) { server in
                HStack(spacing: 10) {
                    NavigationLink {
                        FMOV4ServerDetailView(server: server)
                    } label: {
                        serverLabel(server)
                    }
                    Button {
                        toggleFavorite(server)
                    } label: {
                        Image(systemName: isFavorite(server) ? "star.fill" : "star")
                            .foregroundStyle(isFavorite(server) ? Color.accentColor : .secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFavorite(server) ? "取消收藏 \(server.name)" : "收藏 \(server.name)")
                }
            }
        }
    }

    @ViewBuilder
    private var favoritesSections: some View {
        Section("收藏呼号 · \(filteredFavoriteCallsigns.count)") {
            ForEach(filteredFavoriteCallsigns) { favorite in
                if let station = station(for: favorite) {
                    HStack(spacing: 10) {
                        NavigationLink { FMOV4StationDetailView(station: station) } label: {
                            stationLabel(station)
                        }
                        removeFavoriteButton(favorite, label: favorite.displayCallsign)
                    }
                } else {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(favorite.displayCallsign).font(.body.weight(.semibold))
                            Text("当前未收到数据").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        removeFavoriteButton(favorite, label: favorite.displayCallsign)
                    }
                }
            }
        }

        Section("收藏服务器 · \(filteredFavoriteServers.count)") {
            ForEach(filteredFavoriteServers) { favorite in
                if let server = server(for: favorite) {
                    HStack(spacing: 10) {
                        NavigationLink { FMOV4ServerDetailView(server: server) } label: {
                            serverLabel(server)
                        }
                        removeFavoriteButton(favorite, label: favorite.displayName)
                    }
                } else {
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(favorite.displayName).font(.body.weight(.semibold))
                            Text("当前未收到数据").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        removeFavoriteButton(favorite, label: favorite.displayName)
                    }
                }
            }
        }
    }

    private func stationLabel(_ station: FMOV4StationRecord) -> some View {
        let tint = station.lastActivity?.tint ?? Color.accentColor
        return HStack(spacing: 11) {
            Image(systemName: station.lastActivity?.symbol ?? "person.wave.2")
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.1), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(station.id).font(.body.weight(.semibold).monospaced())
                Text(station.observedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fullWidthRowHitArea()
    }

    private func serverLabel(_ server: FMOV4ServerRecord) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "server.rack")
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.1), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(server.name).font(.body.weight(.semibold)).lineLimit(1)
                Text("\(server.onlineUserCount) 在线 · \(server.filterKilometers) km")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fullWidthRowHitArea()
    }

    private var filteredStations: [FMOV4StationRecord] {
        guard !normalizedSearch.isEmpty else { return snapshot.stations }
        return snapshot.stations.filter {
            $0.id.localizedCaseInsensitiveContains(normalizedSearch)
                || $0.frequency?.localizedCaseInsensitiveContains(normalizedSearch) == true
        }
    }

    private var filteredServers: [FMOV4ServerRecord] {
        guard !normalizedSearch.isEmpty else { return snapshot.servers }
        return snapshot.servers.filter {
            $0.name.localizedCaseInsensitiveContains(normalizedSearch)
                || $0.host.localizedCaseInsensitiveContains(normalizedSearch)
                || $0.countryCode.localizedCaseInsensitiveContains(normalizedSearch)
        }
    }

    private var filteredFavoriteCallsigns: [FavoriteCallsign] {
        guard !normalizedSearch.isEmpty else { return favoriteCallsigns }
        return favoriteCallsigns.filter { $0.displayCallsign.localizedCaseInsensitiveContains(normalizedSearch) }
    }

    private var filteredFavoriteServers: [FavoriteServer] {
        guard !normalizedSearch.isEmpty else { return favoriteServers }
        return favoriteServers.filter { $0.displayName.localizedCaseInsensitiveContains(normalizedSearch) }
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleCount: Int {
        switch segment {
        case .stations: filteredStations.count
        case .servers: filteredServers.count
        case .favorites: filteredFavoriteCallsigns.count + filteredFavoriteServers.count
        }
    }

    private func isFavorite(_ station: FMOV4StationRecord) -> Bool {
        favoriteCallsigns.contains { $0.normalizedCallsign == FMOV4FavoriteKey.callsign(station.callsign) }
    }

    private func isFavorite(_ server: FMOV4ServerRecord) -> Bool {
        favoriteServers.contains { $0.numericUID == server.uid }
    }

    private func toggleFavorite(_ station: FMOV4StationRecord) {
        if let favorite = favoriteCallsigns.first(where: {
            $0.normalizedCallsign == FMOV4FavoriteKey.callsign(station.callsign)
        }) {
            modelContext.delete(favorite)
        } else {
            modelContext.insert(FavoriteCallsign(callsign: station.callsign, ssid: station.ssid))
        }
        try? modelContext.save()
    }

    private func toggleFavorite(_ server: FMOV4ServerRecord) {
        if let favorite = favoriteServers.first(where: { $0.numericUID == server.uid }) {
            modelContext.delete(favorite)
        } else {
            modelContext.insert(FavoriteServer(uid: server.uid, displayName: server.name))
        }
        try? modelContext.save()
    }

    private func removeFavoriteButton<T: PersistentModel>(_ favorite: T, label: String) -> some View {
        Button {
            modelContext.delete(favorite)
            try? modelContext.save()
        } label: {
            Image(systemName: "star.fill")
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("取消收藏 \(label)")
    }

    private func station(for favorite: FavoriteCallsign) -> FMOV4StationRecord? {
        snapshot.stations.first {
            FMOV4FavoriteKey.callsign($0.callsign) == favorite.normalizedCallsign
        }
    }

    private func server(for favorite: FavoriteServer) -> FMOV4ServerRecord? {
        guard let uid = favorite.numericUID else { return nil }
        return snapshot.servers.first { $0.uid == uid }
    }
}
