import Foundation

nonisolated struct DashboardSpeakerLocation: Codable, Equatable, Sendable {
    let callsign: String
    let coordinate: GeoCoordinate
    let grid: String?
    let areaName: String?
    let updatedAt: Date
}

nonisolated protocol DashboardSpeakerLocationStoring: Sendable {
    func location(for callsign: String) async -> DashboardSpeakerLocation?
    func save(_ location: DashboardSpeakerLocation) async
}

actor UserDefaultsDashboardSpeakerLocationStore: DashboardSpeakerLocationStoring {
    private let defaults: UserDefaults
    private let storageKey: String
    private let maximumRecordCount: Int

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "dashboardSpeakerLocations",
        maximumRecordCount: Int = 200
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.maximumRecordCount = maximumRecordCount
    }

    init(
        suiteName: String,
        storageKey: String = "dashboardSpeakerLocations",
        maximumRecordCount: Int = 200
    ) {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.storageKey = storageKey
        self.maximumRecordCount = maximumRecordCount
    }

    func location(for callsign: String) -> DashboardSpeakerLocation? {
        records()[normalized(callsign)]
    }

    func save(_ location: DashboardSpeakerLocation) {
        var values = records()
        let key = normalized(location.callsign)
        guard !key.isEmpty else { return }
        let previous = values[key]
        values[key] = DashboardSpeakerLocation(
            callsign: key,
            coordinate: location.coordinate,
            grid: location.grid ?? previous?.grid,
            areaName: location.areaName ?? previous?.areaName,
            updatedAt: location.updatedAt
        )
        let trimmed = values.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maximumRecordCount)
        let persisted = Dictionary(uniqueKeysWithValues: trimmed.map {
            (normalized($0.callsign), $0)
        })
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func records() -> [String: DashboardSpeakerLocation] {
        guard let data = defaults.data(forKey: storageKey),
              let values = try? JSONDecoder().decode(
                  [String: DashboardSpeakerLocation].self,
                  from: data
              ) else { return [:] }
        return values
    }

    private func normalized(_ callsign: String) -> String {
        callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

actor VolatileDashboardSpeakerLocationStore: DashboardSpeakerLocationStoring {
    private var values: [String: DashboardSpeakerLocation] = [:]

    func location(for callsign: String) -> DashboardSpeakerLocation? {
        values[normalized(callsign)]
    }

    func save(_ location: DashboardSpeakerLocation) {
        values[normalized(location.callsign)] = location
    }

    private func normalized(_ callsign: String) -> String {
        callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
