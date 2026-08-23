import CryptoKit
import Foundation

nonisolated enum MQTTTransportSecurity: String, Codable, CaseIterable, Sendable {
    case plain
    case tls
}

nonisolated struct FMOServerProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    var dialHost: String
    var targetHost: String
    var mqttPort: UInt16
    var serverUID: UInt32
    var serverCallsign: String
    var serverCertificateFingerprint: Data
    var role: String
    var transportSecurity: MQTTTransportSecurity

    init(
        id: UUID = UUID(),
        displayName: String,
        dialHost: String,
        targetHost: String,
        mqttPort: UInt16,
        serverUID: UInt32,
        serverCallsign: String,
        serverCertificateFingerprint: Data,
        role: String = "user",
        transportSecurity: MQTTTransportSecurity = .tls
    ) {
        self.id = id
        self.displayName = displayName
        self.dialHost = dialHost
        self.targetHost = targetHost
        self.mqttPort = mqttPort
        self.serverUID = serverUID
        self.serverCallsign = serverCallsign.uppercased()
        self.serverCertificateFingerprint = serverCertificateFingerprint
        self.role = role
        self.transportSecurity = transportSecurity
    }
}

nonisolated enum VerifiedFMOServerProfileError: Error, Equatable, Sendable {
    case unsupportedUID
    case invalidCertificateFingerprint
}

extension FMOServerProfile {
    nonisolated init(verifiedServer server: FMOV4ServerRecord, id: UUID = UUID()) throws {
        guard let serverUID = UInt32(exactly: server.uid) else {
            throw VerifiedFMOServerProfileError.unsupportedUID
        }
        guard server.certificateFingerprint.count == 32 else {
            throw VerifiedFMOServerProfileError.invalidCertificateFingerprint
        }
        self.init(
            id: id,
            displayName: server.name,
            dialHost: server.host,
            targetHost: server.host,
            mqttPort: server.port,
            serverUID: serverUID,
            serverCallsign: server.certificateCallsign,
            serverCertificateFingerprint: server.certificateFingerprint,
            role: "user",
            transportSecurity: server.port == 8_883 ? .tls : .plain
        )
    }
}

nonisolated struct FMOMQTTConnectRequest: Equatable, Sendable {
    let host: String
    let port: UInt16
    let clientID: String
    let username: String
    let password: String
    let usesTLS: Bool
    let tlsServerName: String?
    let keepAliveSeconds: UInt16
}

nonisolated enum SASAuthPayloadError: Error, Equatable, Sendable {
    case invalidServerProfile
    case invalidCertificateJSON
    case encodingFailure
}

nonisolated struct SASAuthPayloadBuilder: Sendable {
    func makeRequest(
        identity: DirectVoiceIdentity,
        profile: FMOServerProfile,
        installSuffix: String,
        timestamp: UInt64,
        signer: @Sendable (Data) async throws -> Data
    ) async throws -> FMOMQTTConnectRequest {
        guard profile.serverCertificateFingerprint.count == 32,
              !profile.targetHost.isEmpty, !profile.dialHost.isEmpty,
              profile.role == "user" || profile.role == "admin" || profile.role == "super" else {
            throw SASAuthPayloadError.invalidServerProfile
        }
        let userTBS = try DeterministicCBOR().encode(.array([
            .text("FMO"), .unsigned(4), .text("userCert"),
            .unsigned(identity.issuerSerialNumber), .text(identity.callsign.uppercased()),
            .unsigned(UInt64(identity.uid)), .bytes(try publicKey(from: identity.userCertificateJSON)),
            .unsigned(identity.issuedAt), .unsigned(identity.expiresAt),
        ]))
        let userFingerprint = Data(SHA256.hash(data: userTBS))
        let proofTBS = try DeterministicCBOR().encode(.array([
            .text("FMO"), .unsigned(4), .text("serverAuthorizerReqHttp"),
            .unsigned(UInt64(profile.serverUID)), .text(profile.serverCallsign.uppercased()),
            .unsigned(UInt64(profile.serverUID)), .text(profile.role), .text(profile.targetHost),
            .unsigned(UInt64(profile.mqttPort)), .bytes(profile.serverCertificateFingerprint),
            .unsigned(timestamp), .bytes(userFingerprint),
        ]))
        let signature = try await signer(proofTBS)
        let passwordJSON = try makePasswordJSON(
            identity: identity,
            profile: profile,
            timestamp: timestamp,
            signature: signature
        )
        return FMOMQTTConnectRequest(
            host: profile.dialHost,
            port: profile.mqttPort,
            clientID: "fmoc-ios-\(identity.uid)-\(installSuffix)",
            username: identity.callsign.uppercased(),
            password: FMOV4Base64URL.encode(passwordJSON),
            usesTLS: profile.transportSecurity == .tls,
            tlsServerName: profile.transportSecurity == .tls ? profile.targetHost : nil,
            keepAliveSeconds: 30
        )
    }

    private func publicKey(from userJSON: Data) throws -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: userJSON) as? [String: Any],
              let subject = object["subject"] as? [String: Any],
              let encoded = subject["publicKey"] as? String,
              let result = try? FMOV4Base64URL.decode(encoded, requiredByteCount: 32) else {
            throw SASAuthPayloadError.invalidCertificateJSON
        }
        return result
    }

    private func makePasswordJSON(
        identity: DirectVoiceIdentity,
        profile: FMOServerProfile,
        timestamp: UInt64,
        signature: Data
    ) throws -> Data {
        guard let intermediate = try? JSONSerialization.jsonObject(with: identity.intermediateCertificateJSON),
              let user = try? JSONSerialization.jsonObject(with: identity.userCertificateJSON) else {
            throw SASAuthPayloadError.invalidCertificateJSON
        }
        let object: [String: Any] = [
            "certPackage": ["intermediateCert": intermediate, "userCert": user],
            "targetCallsign": profile.serverCallsign.uppercased(),
            "targetUID": profile.serverUID,
            "role": profile.role,
            "targetUrl": profile.targetHost,
            "targetPort": profile.mqttPort,
            "serverFingerprint": FMOV4Base64URL.encode(profile.serverCertificateFingerprint),
            "timestamp": timestamp,
            "proof": ["signature": FMOV4Base64URL.encode(signature)],
        ]
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            throw SASAuthPayloadError.encodingFailure
        }
        return data
    }
}

nonisolated final class UserDefaultsFMOServerProfileStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "directVoiceServerProfile") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> FMOServerProfile? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(FMOServerProfile.self, from: $0) }
    }

    func save(_ profile: FMOServerProfile) throws {
        defaults.set(try JSONEncoder().encode(profile), forKey: key)
    }

    func remove() {
        defaults.removeObject(forKey: key)
    }
}

nonisolated final class UserDefaultsVerifiedFMOServerCatalogStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "directVoiceVerifiedServerCatalog") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [FMOServerProfile] {
        guard let data = defaults.data(forKey: key),
              let profiles = try? JSONDecoder().decode([FMOServerProfile].self, from: data) else {
            return []
        }
        return profiles.filter(Self.isValid)
    }

    func save(_ profiles: [FMOServerProfile]) throws {
        defaults.set(try JSONEncoder().encode(profiles.filter(Self.isValid)), forKey: key)
    }

    func merging(
        verifiedServers: [FMOV4ServerRecord],
        into existingProfiles: [FMOServerProfile]
    ) -> [FMOServerProfile] {
        var profilesByUID: [UInt32: FMOServerProfile] = [:]
        for profile in existingProfiles where Self.isValid(profile) {
            profilesByUID[profile.serverUID] = profile
        }
        for server in verifiedServers {
            guard let serverUID = UInt32(exactly: server.uid) else { continue }
            let id = profilesByUID[serverUID]?.id ?? UUID()
            guard let profile = try? FMOServerProfile(verifiedServer: server, id: id) else { continue }
            profilesByUID[serverUID] = profile
        }
        return profilesByUID.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private static func isValid(_ profile: FMOServerProfile) -> Bool {
        !profile.displayName.isEmpty
            && !profile.dialHost.isEmpty
            && !profile.targetHost.isEmpty
            && !profile.serverCallsign.isEmpty
            && profile.serverCertificateFingerprint.count == 32
            && profile.role == "user"
    }
}
