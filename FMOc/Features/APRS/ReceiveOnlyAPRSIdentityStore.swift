import Foundation

nonisolated enum ReceiveOnlyAPRSIdentitySource: String, Equatable, Sendable {
    case inherited
    case manual
}

nonisolated struct ReceiveOnlyAPRSIdentityConfiguration: Equatable, Sendable {
    let identity: ReceiveOnlyAPRSIdentity
    let source: ReceiveOnlyAPRSIdentitySource
}

nonisolated protocol ReceiveOnlyAPRSIdentityStoring: Sendable {
    func load() async -> ReceiveOnlyAPRSIdentityConfiguration?
    func saveManual(_ identity: ReceiveOnlyAPRSIdentity) async
    func adoptInherited(_ identity: ReceiveOnlyAPRSIdentity) async
}

actor UserDefaultsReceiveOnlyAPRSIdentityStore: ReceiveOnlyAPRSIdentityStoring {
    private enum Key {
        static let callsign = "aprs.receiveOnlyIdentity.callsign"
        static let ssid = "aprs.receiveOnlyIdentity.ssid"
        static let source = "aprs.receiveOnlyIdentity.source"
    }

    private let defaults: UserDefaults

    init(suiteName: String? = nil) {
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            self.defaults = defaults
        } else {
            defaults = .standard
        }
    }

    func load() -> ReceiveOnlyAPRSIdentityConfiguration? {
        guard
            let callsign = defaults.string(forKey: Key.callsign),
            let sourceValue = defaults.string(forKey: Key.source),
            let source = ReceiveOnlyAPRSIdentitySource(rawValue: sourceValue),
            let identity = try? ReceiveOnlyAPRSIdentity(
                callsign: callsign,
                ssid: defaults.integer(forKey: Key.ssid)
            )
        else {
            return nil
        }

        return ReceiveOnlyAPRSIdentityConfiguration(identity: identity, source: source)
    }

    func saveManual(_ identity: ReceiveOnlyAPRSIdentity) {
        save(identity, source: .manual)
    }

    func adoptInherited(_ identity: ReceiveOnlyAPRSIdentity) {
        if load()?.source == .manual {
            return
        }
        save(identity, source: .inherited)
    }

    private func save(
        _ identity: ReceiveOnlyAPRSIdentity,
        source: ReceiveOnlyAPRSIdentitySource
    ) {
        defaults.set(identity.callsign, forKey: Key.callsign)
        defaults.set(Int(identity.ssid), forKey: Key.ssid)
        defaults.set(source.rawValue, forKey: Key.source)
    }
}
