import Foundation
import Network

nonisolated enum NetworkPathState: Equatable, Sendable {
    case available
    case unavailable
}

nonisolated protocol NetworkPathObserving: Sendable {
    func updates() -> AsyncStream<NetworkPathState>
}

nonisolated struct NWPathNetworkObserver: NetworkPathObserving {
    func updates() -> AsyncStream<NetworkPathState> {
        let box = NWPathMonitorBox()

        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            box.monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied ? .available : .unavailable)
            }
            continuation.onTermination = { _ in
                box.monitor.cancel()
            }
            box.monitor.start(queue: box.queue)
        }
    }
}

private nonisolated final class NWPathMonitorBox: @unchecked Sendable {
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "com.bi8syn.FMOc.location-network-path")
}
