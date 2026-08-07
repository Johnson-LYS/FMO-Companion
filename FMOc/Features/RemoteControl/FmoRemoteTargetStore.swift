import Foundation

protocol FmoRemoteTargetStoring: Actor {
    func load() async -> TNC2Address?
    func save(_ target: TNC2Address) async
}

actor UserDefaultsFmoRemoteTargetStore: FmoRemoteTargetStoring {
    private let defaults: UserDefaults
    private let key = "fmo.remoteControl.target"

    init(suiteName: String? = nil) {
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            self.defaults = defaults
        } else {
            defaults = .standard
        }
    }

    func load() -> TNC2Address? {
        guard let value = defaults.string(forKey: key) else { return nil }
        return try? APRSMessageCodec().parseAddress(value)
    }

    func save(_ target: TNC2Address) {
        defaults.set(target.formatted, forKey: key)
    }
}
