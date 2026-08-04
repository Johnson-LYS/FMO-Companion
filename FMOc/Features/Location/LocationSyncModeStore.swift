import Foundation

nonisolated protocol LocationSyncModeStoring: Sendable {
    func load() async -> LocationSyncMode
    func save(_ mode: LocationSyncMode) async
}

actor UserDefaultsLocationSyncModeStore: LocationSyncModeStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "locationSyncMode") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> LocationSyncMode {
        guard
            let rawValue = defaults.string(forKey: key),
            let mode = LocationSyncMode(rawValue: rawValue)
        else {
            return .manual
        }

        return mode
    }

    func save(_ mode: LocationSyncMode) {
        defaults.set(mode.rawValue, forKey: key)
    }
}
