import Foundation

actor AutomaticLocationSyncCoordinator: AutomaticLocationSyncCoordinating {
    private let locationProvider: any AutomaticLocationProviding
    private let networkObserver: any NetworkPathObserving
    private let geoClient: any FmoGeoClient
    private let endpointStore: any FmoEndpointStoring
    private let modeStore: any LocationSyncModeStoring
    private let evaluator: LocationSyncEvaluator
    private let backoffPolicy: LocationSyncBackoffPolicy
    private let waiter: any RetryWaiting
    private let dateProvider: any DateProviding

    private var snapshot = AutomaticLocationSyncSnapshot()
    private var lastSuccessfulSample: LocationSyncSample?
    private var latestSample: LocationSyncSample?
    private var networkState: NetworkPathState = .unavailable
    private var generation = UUID()
    private var locationTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var observers: [
        UUID: AsyncStream<AutomaticLocationSyncSnapshot>.Continuation
    ] = [:]

    init(
        locationProvider: any AutomaticLocationProviding,
        networkObserver: any NetworkPathObserving,
        geoClient: any FmoGeoClient,
        endpointStore: any FmoEndpointStoring,
        modeStore: any LocationSyncModeStoring,
        evaluator: LocationSyncEvaluator = LocationSyncEvaluator(),
        backoffPolicy: LocationSyncBackoffPolicy = .default,
        waiter: any RetryWaiting = TaskRetryWaiter(),
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.locationProvider = locationProvider
        self.networkObserver = networkObserver
        self.geoClient = geoClient
        self.endpointStore = endpointStore
        self.modeStore = modeStore
        self.evaluator = evaluator
        self.backoffPolicy = backoffPolicy
        self.waiter = waiter
        self.dateProvider = dateProvider
    }

    func restore() async {
        await startRuntime(mode: await modeStore.load(), persistMode: false)
    }

    func start(mode: LocationSyncMode) async {
        await startRuntime(mode: mode, persistMode: true)
    }

    func stop() async {
        await stopRuntime()
        await modeStore.save(.manual)
        snapshot.mode = .manual
        snapshot.phase = .stopped
        publish()
    }

    func resume() {
        guard snapshot.mode != .manual, networkState == .available, latestSample != nil else {
            return
        }
        scheduleSync(cause: .networkRecovery)
    }

    func currentSnapshot() -> AutomaticLocationSyncSnapshot {
        snapshot
    }

    func snapshots() -> AsyncStream<AutomaticLocationSyncSnapshot> {
        let observerID = UUID()
        let (stream, continuation) = AsyncStream<
            AutomaticLocationSyncSnapshot
        >.makeStream(bufferingPolicy: .bufferingNewest(1))

        observers[observerID] = continuation
        continuation.yield(snapshot)
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeObserver(observerID)
            }
        }
        return stream
    }

    private func startRuntime(mode: LocationSyncMode, persistMode: Bool) async {
        await stopRuntime()

        if persistMode {
            await modeStore.save(mode)
        }
        snapshot.mode = mode

        guard mode != .manual else {
            snapshot.phase = .stopped
            publish()
            return
        }

        generation = UUID()
        let currentGeneration = generation
        networkState = .unavailable
        lastSuccessfulSample = nil
        snapshot.phase = .starting
        publish()

        do {
            let locationUpdates = try await locationProvider.updates(for: mode)
            let networkUpdates = networkObserver.updates()

            locationTask = Task { [weak self] in
                do {
                    for try await event in locationUpdates {
                        guard !Task.isCancelled else { return }
                        await self?.handleLocationEvent(event, generation: currentGeneration)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    await self?.handleLocationStreamFailure(generation: currentGeneration)
                }
            }

            networkTask = Task { [weak self] in
                for await state in networkUpdates {
                    guard !Task.isCancelled else { return }
                    await self?.handleNetworkState(state, generation: currentGeneration)
                }
            }

            snapshot.phase = .waitingForLocation
            publish()
        } catch {
            snapshot.phase = .paused(.locationStreamFailed)
            publish()
        }
    }

    private func stopRuntime() async {
        generation = UUID()
        locationTask?.cancel()
        networkTask?.cancel()
        syncTask?.cancel()
        locationTask = nil
        networkTask = nil
        syncTask = nil
        latestSample = nil
        lastSuccessfulSample = nil
        networkState = .unavailable

        await locationProvider.stop()
        await geoClient.disconnect()
    }

    private func handleLocationEvent(
        _ event: AutomaticLocationEvent,
        generation: UUID
    ) async {
        guard self.generation == generation, snapshot.mode != .manual else { return }

        switch event {
        case .location(let sample):
            latestSample = sample.syncSample
            guard syncTask == nil else { return }

            switch evaluator.evaluate(
                mode: snapshot.mode,
                candidate: sample.syncSample,
                lastSuccessfulSync: lastSuccessfulSample
            ) {
            case .manualOnly:
                return
            case .throttled:
                snapshot.phase = .waitingForLocation
                publish()
            case .synchronize(let trigger):
                guard networkState == .available else {
                    snapshot.phase = .paused(.networkUnavailable)
                    publish()
                    return
                }
                scheduleSync(cause: .location(trigger))
            }

        case .paused(let reason):
            snapshot.phase = .paused(.location(reason))
            publish()

            if reason.stopsActiveSync {
                syncTask?.cancel()
                syncTask = nil
                await geoClient.disconnect()
            }
        }
    }

    private func handleLocationStreamFailure(generation: UUID) async {
        guard self.generation == generation, snapshot.mode != .manual else { return }
        syncTask?.cancel()
        syncTask = nil
        snapshot.phase = .paused(.locationStreamFailed)
        publish()
        await geoClient.disconnect()
    }

    private func handleNetworkState(_ state: NetworkPathState, generation: UUID) async {
        guard self.generation == generation, snapshot.mode != .manual else { return }
        let previousState = networkState
        networkState = state

        switch state {
        case .unavailable:
            syncTask?.cancel()
            syncTask = nil
            snapshot.phase = .paused(.networkUnavailable)
            publish()
            await geoClient.disconnect()

        case .available:
            guard latestSample != nil else {
                if case .paused(.location) = snapshot.phase { return }
                snapshot.phase = .waitingForLocation
                publish()
                return
            }
            guard previousState == .unavailable else { return }
            scheduleSync(cause: .networkRecovery)
        }
    }

    private func scheduleSync(cause: AutomaticLocationSyncCause) {
        guard syncTask == nil, latestSample != nil, snapshot.mode != .manual else { return }
        let currentGeneration = generation
        syncTask = Task { [weak self] in
            await self?.runSyncLoop(initialCause: cause, generation: currentGeneration)
        }
    }

    private func runSyncLoop(
        initialCause: AutomaticLocationSyncCause,
        generation: UUID
    ) async {
        var retry = 0
        var cause = initialCause

        while self.generation == generation, !Task.isCancelled {
            guard networkState == .available else {
                finishSyncTask(generation: generation)
                snapshot.phase = .paused(.networkUnavailable)
                publish()
                return
            }
            guard let sample = latestSample else {
                finishSyncTask(generation: generation)
                snapshot.phase = .waitingForLocation
                publish()
                return
            }
            guard let endpoint = await endpointStore.load() else {
                finishSyncTask(generation: generation)
                snapshot.phase = .paused(.noDevice)
                publish()
                return
            }
            guard
                self.generation == generation,
                !Task.isCancelled,
                networkState == .available
            else {
                finishSyncTask(generation: generation)
                return
            }

            let attemptTime = dateProvider.now()
            snapshot.phase = .syncing(cause)
            snapshot.lastAttempt = LocationSyncAttempt(
                timestamp: attemptTime,
                result: .inProgress
            )
            publish()

            do {
                try await geoClient.connect(to: endpoint)
                try Task.checkCancellation()
                try await geoClient.setCoordinate(sample.coordinate)
                try Task.checkCancellation()

                lastSuccessfulSample = sample
                snapshot.lastAttempt = LocationSyncAttempt(
                    timestamp: attemptTime,
                    result: .success
                )
                snapshot.lastSuccessAt = dateProvider.now()
                snapshot.phase = .waitingForLocation
                publish()

                retry = 0
                if let pendingTrigger = pendingTrigger(after: sample) {
                    cause = .location(pendingTrigger)
                    continue
                }

                finishSyncTask(generation: generation)
                return
            } catch is CancellationError {
                finishSyncTask(generation: generation)
                return
            } catch let error as FmoDeviceError where error == .operationCancelled {
                finishSyncTask(generation: generation)
                return
            } catch {
                await geoClient.disconnect()
                guard self.generation == generation, !Task.isCancelled else {
                    finishSyncTask(generation: generation)
                    return
                }

                let deviceError = Self.deviceError(from: error)
                snapshot.lastAttempt = LocationSyncAttempt(
                    timestamp: attemptTime,
                    result: .failure(deviceError)
                )

                guard networkState == .available else {
                    finishSyncTask(generation: generation)
                    snapshot.phase = .paused(.networkUnavailable)
                    publish()
                    return
                }

                let delay = backoffPolicy.delay(forRetry: retry)
                retry += 1
                snapshot.phase = .retrying(attempt: retry, delay: delay)
                publish()

                do {
                    try await waiter.wait(for: delay)
                    try Task.checkCancellation()
                    cause = .retry
                } catch {
                    finishSyncTask(generation: generation)
                    return
                }
            }
        }

        finishSyncTask(generation: generation)
    }

    private func pendingTrigger(after sentSample: LocationSyncSample) -> LocationSyncTrigger? {
        guard let latestSample, latestSample != sentSample else { return nil }
        guard case .synchronize(let trigger) = evaluator.evaluate(
            mode: snapshot.mode,
            candidate: latestSample,
            lastSuccessfulSync: lastSuccessfulSample
        ) else {
            return nil
        }
        return trigger
    }

    private func finishSyncTask(generation: UUID) {
        guard self.generation == generation else { return }
        syncTask = nil
    }

    private func publish() {
        for continuation in observers.values {
            continuation.yield(snapshot)
        }
    }

    private func removeObserver(_ observerID: UUID) {
        observers.removeValue(forKey: observerID)
    }

    private nonisolated static func deviceError(from error: any Error) -> FmoDeviceError {
        if let error = error as? FmoDeviceError { return error }
        return .disconnected
    }
}

private extension AutomaticLocationPauseReason {
    nonisolated var stopsActiveSync: Bool {
        switch self {
        case .authorizationRequestInProgress, .locationUnavailable, .stationary:
            false
        case .authorizationDenied,
             .authorizationRestricted,
             .alwaysAuthorizationRequired,
             .locationServicesDisabled,
             .insufficientlyInUse,
             .serviceSessionRequired:
            true
        }
    }
}
