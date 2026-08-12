import CoreLocation
import Foundation

nonisolated struct PhoneLocationSample: Equatable, Sendable {
    let coordinate: GeoCoordinate
    let horizontalAccuracy: Double
    let isAccuracyLimited: Bool
}

nonisolated enum PhoneLocationError: Error, Equatable, Sendable {
    case denied
    case restricted
    case unavailable
    case timedOut
    case invalidCoordinate
}

extension PhoneLocationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .denied: String(localized: "定位访问已关闭")
        case .restricted: String(localized: "当前设备限制了定位访问")
        case .unavailable: String(localized: "暂时无法获取当前位置")
        case .timedOut: String(localized: "没有在 15 秒内获得可用位置")
        case .invalidCoordinate: String(localized: "系统返回了无效坐标")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .denied: String(localized: "请前往系统设置允许定位访问。")
        case .restricted: String(localized: "请检查屏幕使用时间或设备管理中的定位限制。")
        case .unavailable: String(localized: "请到视野开阔处后重试。")
        case .timedOut: String(localized: "请确认定位服务已开启后重试。")
        case .invalidCoordinate: String(localized: "请重新获取位置。")
        }
    }
}

nonisolated protocol PhoneLocationProviding: Sendable {
    func currentLocation() async throws -> PhoneLocationSample
}

actor CoreLocationProvider: PhoneLocationProviding {
    nonisolated struct Policy: Sendable {
        var desiredHorizontalAccuracy: Double = 100
        var maximumCachedAge: Duration = .seconds(10)
        var timeout: Duration = .seconds(15)
    }

    private let policy: Policy

    init(policy: Policy = Policy()) {
        self.policy = policy
    }

    func currentLocation() async throws -> PhoneLocationSample {
        let policy = self.policy
        return try await withThrowingTaskGroup(of: PhoneLocationSample.self) { group in
            group.addTask {
                let session = CLServiceSession(authorization: .whenInUse)
                defer { session.invalidate() }

                for try await update in CLLocationUpdate.liveUpdates(.default) {
                    if update.authorizationDenied { throw PhoneLocationError.denied }
                    if update.authorizationRestricted { throw PhoneLocationError.restricted }
                    if update.locationUnavailable { continue }
                    guard let location = update.location, location.horizontalAccuracy >= 0 else { continue }

                    let age = Date.now.timeIntervalSince(location.timestamp)
                    let maximumAge = TimeInterval(policy.maximumCachedAge.components.seconds)
                    guard age <= maximumAge else { continue }

                    guard let coordinate = try? GeoCoordinate(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    ) else { throw PhoneLocationError.invalidCoordinate }

                    if location.horizontalAccuracy <= policy.desiredHorizontalAccuracy {
                        return PhoneLocationSample(
                            coordinate: coordinate,
                            horizontalAccuracy: location.horizontalAccuracy,
                            isAccuracyLimited: update.accuracyLimited
                        )
                    }
                }
                throw PhoneLocationError.unavailable
            }
            group.addTask {
                try await Task.sleep(for: policy.timeout)
                throw PhoneLocationError.timedOut
            }

            defer { group.cancelAll() }
            guard let sample = try await group.next() else { throw PhoneLocationError.unavailable }
            return sample
        }
    }
}
