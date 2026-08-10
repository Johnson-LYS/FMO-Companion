import CryptoKit
import Foundation

nonisolated enum FmoRemoteControlError: Error, Equatable, Sendable {
    case invalidSource
    case invalidTarget
    case invalidSecret
    case invalidTimeSlot
    case invalidCounter
}

nonisolated enum FmoRemoteAction: String, CaseIterable, Codable, Sendable {
    case normal = "NORMAL"
    case standby = "STANDBY"
    case reboot = "REBOOT"
}

nonisolated struct FmoRemoteCommand: Equatable, Sendable {
    let source: TNC2Address
    let target: TNC2Address
    let action: FmoRemoteAction
    let timeSlot: UInt64
    let counter: UInt64
}

nonisolated struct FmoRemoteControlCodec: Sendable {
    static let destination = "APFMO0"

    func timeSlot(for date: Date) throws -> UInt64 {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, seconds >= 0 else {
            throw FmoRemoteControlError.invalidTimeSlot
        }
        return UInt64(floor(seconds / 60))
    }

    func signature(for command: FmoRemoteCommand, secret: String) throws -> String {
        try validate(command)
        guard
            secret.utf8.count == 12,
            secret.utf8.allSatisfy(Self.isUppercaseASCIIAlphanumeric)
        else {
            throw FmoRemoteControlError.invalidSecret
        }

        let raw = [
            command.source.callsign,
            String(command.source.ssid),
            "CONTROL",
            command.action.rawValue,
            String(command.timeSlot),
            String(command.counter),
        ].joined()
        let authenticationCode = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(raw.utf8),
            using: SymmetricKey(data: Data(secret.utf8))
        )
        return authenticationCode.prefix(8).map { String(format: "%02X", $0) }.joined()
    }

    func encode(_ command: FmoRemoteCommand, secret: String) throws -> String {
        let signature = try signature(for: command, secret: secret)
        let addressee = try paddedTarget(command.target)
        let payload = [
            "CONTROL",
            command.action.rawValue,
            String(command.timeSlot),
            String(command.counter),
            signature,
        ].joined(separator: ",")
        return "\(command.source.callsign)-\(command.source.ssid)>\(Self.destination),TCPIP*::\(addressee):\(payload)"
    }

    private func validate(_ command: FmoRemoteCommand) throws {
        guard
            (3 ... 6).contains(command.source.callsign.utf8.count),
            command.source.callsign.utf8.allSatisfy(Self.isUppercaseASCIIAlphanumeric),
            command.source.ssid <= 15
        else {
            throw FmoRemoteControlError.invalidSource
        }
        guard command.timeSlot > 0 else {
            throw FmoRemoteControlError.invalidTimeSlot
        }
    }

    private func paddedTarget(_ target: TNC2Address) throws -> String {
        guard
            (3 ... 9).contains(target.formatted.utf8.count),
            target.callsign.utf8.allSatisfy(Self.isUppercaseASCIIAlphanumeric),
            target.ssid <= 15
        else {
            throw FmoRemoteControlError.invalidTarget
        }
        return target.formatted.padding(toLength: 9, withPad: " ", startingAt: 0)
    }

    private static func isUppercaseASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (48 ... 57).contains(byte) || (65 ... 90).contains(byte)
    }
}
