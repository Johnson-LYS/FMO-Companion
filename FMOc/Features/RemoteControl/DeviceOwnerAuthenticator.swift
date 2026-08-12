import LocalAuthentication

protocol DeviceOwnerAuthenticating: Sendable {
    func authorizeReboot() async -> Bool
}

struct LocalDeviceOwnerAuthenticator: DeviceOwnerAuthenticating {
    func authorizeReboot() async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "确认重启远程 FMO 设备")
            )
        } catch {
            return false
        }
    }
}
