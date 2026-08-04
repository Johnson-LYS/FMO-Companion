import CoreLocation
import Foundation

nonisolated struct AutomaticLocationSample: Equatable, Sendable {
    let syncSample: LocationSyncSample
    let horizontalAccuracy: Double
    let isAccuracyLimited: Bool
}

nonisolated enum AutomaticLocationPauseReason: Equatable, Sendable {
    case authorizationRequestInProgress
    case authorizationDenied
    case authorizationRestricted
    case alwaysAuthorizationRequired
    case locationServicesDisabled
    case insufficientlyInUse
    case serviceSessionRequired
    case locationUnavailable
    case stationary
}

nonisolated enum AutomaticLocationEvent: Equatable, Sendable {
    case location(AutomaticLocationSample)
    case paused(AutomaticLocationPauseReason)
}

nonisolated enum AutomaticLocationError: Error, Equatable, Sendable {
    case manualMode
    case invalidCoordinate
}

nonisolated protocol AutomaticLocationProviding: Sendable {
    func updates(
        for mode: LocationSyncMode
    ) async throws -> AsyncThrowingStream<AutomaticLocationEvent, any Error>
    func stop() async
}

actor CoreLocationAutomaticProvider: AutomaticLocationProviding {
    private var serviceSession: CLServiceSession?
    private var backgroundSession: CLBackgroundActivitySession?
    private var updateTask: Task<Void, Never>?
    private var serviceDiagnosticTask: Task<Void, Never>?
    private var backgroundDiagnosticTask: Task<Void, Never>?
    private var continuation: AsyncThrowingStream<AutomaticLocationEvent, any Error>.Continuation?
    private var activeStreamID: UUID?

    func updates(
        for mode: LocationSyncMode
    ) async throws -> AsyncThrowingStream<AutomaticLocationEvent, any Error> {
        guard mode != .manual else {
            throw AutomaticLocationError.manualMode
        }

        stopActiveStream()

        let streamID = UUID()
        let serviceSession = CLServiceSession(authorization: .always)
        let backgroundSession = CLBackgroundActivitySession()
        let configuration: CLLocationUpdate.LiveConfiguration = mode == .vehicle
            ? .automotiveNavigation
            : .default
        let liveUpdates = CLLocationUpdate.liveUpdates(configuration)
        let (stream, continuation) = AsyncThrowingStream<
            AutomaticLocationEvent,
            any Error
        >.makeStream(bufferingPolicy: .bufferingNewest(1))

        self.activeStreamID = streamID
        self.serviceSession = serviceSession
        self.backgroundSession = backgroundSession
        self.continuation = continuation

        updateTask = Task {
            do {
                for try await update in liveUpdates {
                    try Task.checkCancellation()

                    if let pauseReason = Self.pauseReason(for: update) {
                        continuation.yield(.paused(pauseReason))
                        continue
                    }

                    guard let location = update.location, location.horizontalAccuracy >= 0 else {
                        if update.stationary {
                            continuation.yield(.paused(.stationary))
                        }
                        continue
                    }
                    guard let coordinate = try? GeoCoordinate(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    ) else {
                        throw AutomaticLocationError.invalidCoordinate
                    }

                    continuation.yield(
                        .location(
                            AutomaticLocationSample(
                                syncSample: LocationSyncSample(
                                    coordinate: coordinate,
                                    timestamp: location.timestamp
                                ),
                                horizontalAccuracy: location.horizontalAccuracy,
                                isAccuracyLimited: update.accuracyLimited
                            )
                        )
                    )
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        serviceDiagnosticTask = Task {
            do {
                for try await diagnostic in serviceSession.diagnostics {
                    try Task.checkCancellation()
                    if let pauseReason = Self.pauseReason(for: diagnostic) {
                        continuation.yield(.paused(pauseReason))
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                continuation.finish(throwing: error)
            }
        }

        backgroundDiagnosticTask = Task {
            do {
                for try await diagnostic in backgroundSession.diagnostics {
                    try Task.checkCancellation()
                    if let pauseReason = Self.pauseReason(for: diagnostic) {
                        continuation.yield(.paused(pauseReason))
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.stop(streamID: streamID)
            }
        }

        return stream
    }

    func stop() {
        stopActiveStream()
    }

    private func stop(streamID: UUID) {
        guard activeStreamID == streamID else { return }
        stopActiveStream()
    }

    private func stopActiveStream() {
        activeStreamID = nil
        updateTask?.cancel()
        serviceDiagnosticTask?.cancel()
        backgroundDiagnosticTask?.cancel()
        continuation?.finish()
        serviceSession?.invalidate()
        backgroundSession?.invalidate()

        updateTask = nil
        serviceDiagnosticTask = nil
        backgroundDiagnosticTask = nil
        continuation = nil
        serviceSession = nil
        backgroundSession = nil
    }

    private nonisolated static func pauseReason(
        for update: CLLocationUpdate
    ) -> AutomaticLocationPauseReason? {
        if update.authorizationRequestInProgress { return .authorizationRequestInProgress }
        if update.authorizationDeniedGlobally { return .locationServicesDisabled }
        if update.authorizationDenied { return .authorizationDenied }
        if update.authorizationRestricted { return .authorizationRestricted }
        if update.insufficientlyInUse { return .insufficientlyInUse }
        if update.serviceSessionRequired { return .serviceSessionRequired }
        if update.locationUnavailable { return .locationUnavailable }
        return nil
    }

    private nonisolated static func pauseReason(
        for diagnostic: CLServiceSession.Diagnostic
    ) -> AutomaticLocationPauseReason? {
        if diagnostic.authorizationRequestInProgress { return .authorizationRequestInProgress }
        if diagnostic.authorizationDeniedGlobally { return .locationServicesDisabled }
        if diagnostic.authorizationDenied { return .authorizationDenied }
        if diagnostic.authorizationRestricted { return .authorizationRestricted }
        if diagnostic.alwaysAuthorizationDenied { return .alwaysAuthorizationRequired }
        if diagnostic.insufficientlyInUse { return .insufficientlyInUse }
        if diagnostic.serviceSessionRequired { return .serviceSessionRequired }
        return nil
    }

    private nonisolated static func pauseReason(
        for diagnostic: CLBackgroundActivitySession.Diagnostic
    ) -> AutomaticLocationPauseReason? {
        if diagnostic.authorizationRequestInProgress { return .authorizationRequestInProgress }
        if diagnostic.authorizationDeniedGlobally { return .locationServicesDisabled }
        if diagnostic.authorizationDenied { return .authorizationDenied }
        if diagnostic.authorizationRestricted { return .authorizationRestricted }
        if diagnostic.insufficientlyInUse { return .insufficientlyInUse }
        if diagnostic.serviceSessionRequired { return .serviceSessionRequired }
        return nil
    }
}
