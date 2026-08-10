import Foundation

nonisolated struct FmoRemoteControlSequence: Equatable, Sendable {
    let timeSlot: UInt64
    let counter: UInt64
}

protocol FmoRemoteControlCounterStoring: Actor {
    func next(for target: TNC2Address, timeSlot: UInt64) -> FmoRemoteControlSequence
}

actor UserDefaultsFmoRemoteControlCounterStore: FmoRemoteControlCounterStoring {
    private struct State: Codable {
        let timeSlot: UInt64
        let counter: UInt64
    }

    private let defaults: UserDefaults
    private let keyPrefix = "fmo.remoteControl.counter."

    init(suiteName: String? = nil) {
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            self.defaults = defaults
        } else {
            defaults = .standard
        }
    }

    func next(for target: TNC2Address, timeSlot: UInt64) -> FmoRemoteControlSequence {
        let key = keyPrefix + target.formatted
        let previous = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) }
        let counter = previous?.timeSlot == timeSlot
            ? previous!.counter + 1
            : 0
        let state = State(timeSlot: timeSlot, counter: counter)
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: key)
        }
        return FmoRemoteControlSequence(timeSlot: timeSlot, counter: counter)
    }
}
