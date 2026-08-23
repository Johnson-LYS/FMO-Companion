import Foundation

nonisolated enum FMOVoiceRouteDecision: Equatable, Sendable {
    case accepted
    case continued
    case preempted(previousUID: UInt32)
    case rejected
}

nonisolated struct FMOVoiceRoute: Equatable, Sendable {
    let uid: UInt32
    let streamBeginUTC: UInt32
    let lastPacketMonotonicMilliseconds: UInt64
}

nonisolated struct FMOVoiceRouteArbiter: Sendable {
    private(set) var current: FMOVoiceRoute?
    let occupancyMilliseconds: UInt64

    init(occupancyMilliseconds: UInt64 = 1_500) {
        self.occupancyMilliseconds = occupancyMilliseconds
    }

    mutating func consider(
        uid: UInt32,
        streamBeginUTC: UInt32,
        nowMilliseconds: UInt64
    ) -> FMOVoiceRouteDecision {
        guard let active = current else {
            current = FMOVoiceRoute(uid: uid, streamBeginUTC: streamBeginUTC, lastPacketMonotonicMilliseconds: nowMilliseconds)
            return .accepted
        }
        if active.uid == uid {
            current = FMOVoiceRoute(uid: uid, streamBeginUTC: streamBeginUTC, lastPacketMonotonicMilliseconds: nowMilliseconds)
            return .continued
        }
        if nowMilliseconds &- active.lastPacketMonotonicMilliseconds > occupancyMilliseconds {
            current = FMOVoiceRoute(uid: uid, streamBeginUTC: streamBeginUTC, lastPacketMonotonicMilliseconds: nowMilliseconds)
            return .preempted(previousUID: active.uid)
        }

        let candidateEarlierBy = Int32(bitPattern: active.streamBeginUTC &- streamBeginUTC)
        let shouldPreempt = (candidateEarlierBy > 0 && candidateEarlierBy <= 2_000)
            || (candidateEarlierBy == 0 && uid < active.uid)
        guard shouldPreempt else { return .rejected }
        current = FMOVoiceRoute(uid: uid, streamBeginUTC: streamBeginUTC, lastPacketMonotonicMilliseconds: nowMilliseconds)
        return .preempted(previousUID: active.uid)
    }

    mutating func reset() {
        current = nil
    }

    func isOccupied(at nowMilliseconds: UInt64, excludingUID uid: UInt32? = nil) -> Bool {
        guard let current, current.uid != uid else { return false }
        return nowMilliseconds &- current.lastPacketMonotonicMilliseconds <= occupancyMilliseconds
    }
}
