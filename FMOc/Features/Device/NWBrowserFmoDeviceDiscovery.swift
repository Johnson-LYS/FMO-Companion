import Foundation
import Network
import Synchronization

nonisolated final class NWBrowserFmoDeviceDiscovery: FmoDeviceDiscovering, @unchecked Sendable {
    func discover(timeout: Duration = .seconds(10)) -> AsyncThrowingStream<FmoDeviceEndpoint, any Error> {
        AsyncThrowingStream { continuation in
            let queue = DispatchQueue(label: "com.bi8syn.FMOc.device-discovery")
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = false
            let browser = NWBrowser(
                for: .bonjour(type: "_http._tcp", domain: "local."),
                using: parameters
            )
            let session = DiscoverySession(browser: browser, continuation: continuation, queue: queue)

            browser.stateUpdateHandler = { state in
                session.handle(state)
            }
            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    session.resolve(result)
                }
            }
            continuation.onTermination = { @Sendable _ in
                session.cancel()
            }

            browser.start(queue: queue)
            Task {
                try? await Task.sleep(for: timeout)
                session.timeout()
            }
        }
    }
}

private nonisolated final class DiscoverySession: @unchecked Sendable {
    private struct State: ~Copyable {
        var isFinished = false
        var yieldedIDs: Set<String> = []
    }

    private let browser: NWBrowser
    private let continuation: AsyncThrowingStream<FmoDeviceEndpoint, any Error>.Continuation
    private let queue: DispatchQueue
    private let state = Mutex(State())

    init(
        browser: NWBrowser,
        continuation: AsyncThrowingStream<FmoDeviceEndpoint, any Error>.Continuation,
        queue: DispatchQueue
    ) {
        self.browser = browser
        self.continuation = continuation
        self.queue = queue
    }

    func handle(_ browserState: NWBrowser.State) {
        switch browserState {
        case .waiting(let error):
            if case .dns(let code) = error, Int32(code) == -65_570 {
                finish(throwing: FmoDeviceError.localNetworkDenied)
            }
        case .failed:
            finish(throwing: FmoDeviceError.networkUnavailable)
        case .cancelled:
            finish()
        case .setup, .ready:
            break
        @unknown default:
            break
        }
    }

    func resolve(_ result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint,
              name.localizedCaseInsensitiveContains("fmo") else { return }

        let connection = NWConnection(to: result.endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self, weak connection] connectionState in
            guard let self, let connection else { return }
            switch connectionState {
            case .ready:
                if case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint {
                    self.yield(host: host.debugDescription, port: Int(port.rawValue), name: name)
                } else {
                    self.yield(host: "fmo.local", port: nil, name: name)
                }
                connection.cancel()
            case .failed:
                self.yield(host: "fmo.local", port: nil, name: name)
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func timeout() {
        let hasResults = state.withLock { !$0.yieldedIDs.isEmpty }
        if hasResults {
            finish()
        } else {
            finish(throwing: FmoDeviceError.discoveryTimedOut)
        }
    }

    func cancel() {
        finish()
    }

    private func yield(host: String, port: Int?, name: String) {
        guard let endpoint = try? FmoDeviceEndpoint(
            host: host,
            port: port,
            source: .bonjour,
            name: name
        ) else { return }

        let shouldYield = state.withLock { state in
            guard !state.isFinished else { return false }
            return state.yieldedIDs.insert(endpoint.id).inserted
        }
        if shouldYield { continuation.yield(endpoint) }
    }

    private func finish(throwing error: (any Error)? = nil) {
        let shouldFinish = state.withLock { state in
            guard !state.isFinished else { return false }
            state.isFinished = true
            return true
        }
        guard shouldFinish else { return }

        browser.cancel()
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}
