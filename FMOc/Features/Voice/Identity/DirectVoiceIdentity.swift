import CryptoKit
import Foundation
import Security

nonisolated enum DirectVoiceIdentityError: Error, Equatable, Sendable {
    case missingPrivateKey
    case missingIdentity
    case invalidCallsign
    case invalidBundle
    case publicKeyMismatch
    case invalidCertificateSignature
    case certificateExpired
    case keychainFailure(OSStatus)
}

nonisolated struct DirectVoiceEnrollmentRequest: Equatable, Sendable {
    let callsign: String
    let publicKeyBase64URL: String
}

nonisolated struct DirectVoiceIdentity: Equatable, Codable, Sendable {
    let callsign: String
    let uid: UInt32
    let issuedAt: UInt64
    let expiresAt: UInt64
    let issuerSerialNumber: UInt64
    let rootFingerprint: Data
    let intermediateCertificateJSON: Data
    let userCertificateJSON: Data

    var stableID: String {
        "\(FMOV4Base64URL.encode(rootFingerprint)):\(uid)"
    }

    func isExpired(at date: Date) -> Bool {
        date.timeIntervalSince1970 >= TimeInterval(expiresAt)
    }
}

protocol DirectVoiceIdentityProviding: Sendable {
    func enrollmentRequest(callsign: String) async throws -> DirectVoiceEnrollmentRequest
    func importSignedBundle(_ data: Data, now: Date) async throws -> DirectVoiceIdentity
    func storedIdentities() async throws -> [DirectVoiceIdentity]
    func currentIdentity(now: Date) async throws -> DirectVoiceIdentity
    func selectIdentity(id: String, now: Date) async throws -> DirectVoiceIdentity
    func sign(_ data: Data, identityID: String) async throws -> Data
    func installationSuffix() async throws -> String
    func removeIdentity(id: String, now: Date) async throws
}

protocol DirectVoiceSecretStoring: Sendable {
    nonisolated func load(account: String) throws -> Data?
    nonisolated func save(_ data: Data, account: String, afterFirstUnlock: Bool) throws
    nonisolated func remove(account: String) throws
}

nonisolated final class KeychainDirectVoiceSecretStore: DirectVoiceSecretStoring, @unchecked Sendable {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func load(account: String) throws -> Data? {
        var query = keyQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw DirectVoiceIdentityError.keychainFailure(status)
        }
        return data
    }

    func save(_ data: Data, account: String, afterFirstUnlock: Bool) throws {
        var insertion = keyQuery(account: account)
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = afterFirstUnlock
            ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(insertion as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DirectVoiceIdentityError.keychainFailure(status)
        }
    }

    func remove(account: String) throws {
        let status = SecItemDelete(keyQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DirectVoiceIdentityError.keychainFailure(status)
        }
    }

    private func keyQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

nonisolated final class KeychainDirectVoiceIdentityProvider: DirectVoiceIdentityProviding, @unchecked Sendable {
    private let legacyAccount = "ed25519-seed"
    private let installationAccount = "installation-suffix"
    private let defaults: UserDefaults
    private let metadataKey: String
    private let collectionKey: String
    private let secretStore: any DirectVoiceSecretStoring

    init(
        service: String = "com.bi8syn.FMOc.direct-voice",
        defaults: UserDefaults = .standard,
        metadataKey: String = "directVoiceIdentity",
        secretStore: (any DirectVoiceSecretStoring)? = nil
    ) {
        self.defaults = defaults
        self.metadataKey = metadataKey
        collectionKey = "\(metadataKey).collection.v1"
        self.secretStore = secretStore ?? KeychainDirectVoiceSecretStore(service: service)
    }

    nonisolated func enrollmentRequest(callsign: String) throws -> DirectVoiceEnrollmentRequest {
        let normalized = try Self.normalizeCallsign(callsign)
        let key = try loadOrCreatePrivateKey(callsign: normalized)
        return DirectVoiceEnrollmentRequest(
            callsign: normalized,
            publicKeyBase64URL: FMOV4Base64URL.encode(key.publicKey.rawRepresentation)
        )
    }

    nonisolated func importSignedBundle(_ data: Data, now: Date = .now) throws -> DirectVoiceIdentity {
        let bundle: SignedIdentityBundle
        do {
            bundle = try JSONDecoder().decode(SignedIdentityBundle.self, from: data)
        } catch {
            throw DirectVoiceIdentityError.invalidBundle
        }
        let callsign = try bundle.normalizedCallsign()
        let key = try loadPrivateKey(callsign: callsign, allowingLegacyMigration: true)
        let verified = try bundle.verifiedIdentity(
            publicKey: key.publicKey.rawRepresentation,
            callsign: callsign,
            now: now
        )
        var collection = try loadCollection()
        collection.identities.removeAll { $0.stableID == verified.stableID }
        collection.identities.append(verified)
        collection.selectedID = verified.stableID
        try saveCollection(collection)
        return verified
    }

    nonisolated func storedIdentities() throws -> [DirectVoiceIdentity] {
        try loadCollection().identities
    }

    nonisolated func currentIdentity(now: Date = .now) throws -> DirectVoiceIdentity {
        var collection = try loadCollection()
        guard !collection.identities.isEmpty else {
            throw DirectVoiceIdentityError.missingIdentity
        }
        let identity: DirectVoiceIdentity
        if let selectedID = collection.selectedID,
           let selected = collection.identities.first(where: { $0.stableID == selectedID }) {
            identity = selected
        } else {
            identity = collection.identities[0]
            collection.selectedID = identity.stableID
            try saveCollection(collection)
        }
        _ = try loadPrivateKey(callsign: identity.callsign, allowingLegacyMigration: true)
        guard !identity.isExpired(at: now) else {
            throw DirectVoiceIdentityError.certificateExpired
        }
        return identity
    }

    nonisolated func selectIdentity(id: String, now: Date = .now) throws -> DirectVoiceIdentity {
        var collection = try loadCollection()
        guard let identity = collection.identities.first(where: { $0.stableID == id }) else {
            throw DirectVoiceIdentityError.missingIdentity
        }
        _ = try loadPrivateKey(callsign: identity.callsign, allowingLegacyMigration: true)
        guard !identity.isExpired(at: now) else {
            throw DirectVoiceIdentityError.certificateExpired
        }
        collection.selectedID = identity.stableID
        try saveCollection(collection)
        return identity
    }

    nonisolated func sign(_ data: Data, identityID: String) throws -> Data {
        let collection = try loadCollection()
        guard let identity = collection.identities.first(where: { $0.stableID == identityID }) else {
            throw DirectVoiceIdentityError.missingIdentity
        }
        return try loadPrivateKey(
            callsign: identity.callsign,
            allowingLegacyMigration: true
        ).signature(for: data)
    }

    nonisolated func installationSuffix() throws -> String {
        if let data = try secretStore.load(account: installationAccount),
           let value = String(data: data, encoding: .utf8), value.count == 8 {
            return value
        }
        var bytes = [UInt8](repeating: 0, count: 4)
        let randomStatus = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw DirectVoiceIdentityError.keychainFailure(randomStatus)
        }
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        try secretStore.save(Data(value.utf8), account: installationAccount, afterFirstUnlock: true)
        return value
    }

    nonisolated func removeIdentity(id: String, now: Date = .now) throws {
        var collection = try loadCollection()
        collection.identities.removeAll { $0.stableID == id }
        if collection.selectedID == id {
            collection.selectedID = collection.identities.first(where: { !$0.isExpired(at: now) })?.stableID
                ?? collection.identities.first?.stableID
        }
        try saveCollection(collection)
    }

    nonisolated private func loadCollection() throws -> StoredDirectVoiceIdentities {
        if let data = defaults.data(forKey: collectionKey) {
            guard let collection = try? JSONDecoder().decode(StoredDirectVoiceIdentities.self, from: data) else {
                throw DirectVoiceIdentityError.invalidBundle
            }
            return collection
        }
        if let legacyData = defaults.data(forKey: metadataKey),
           let legacyIdentity = try? JSONDecoder().decode(DirectVoiceIdentity.self, from: legacyData) {
            let collection = StoredDirectVoiceIdentities(
                identities: [legacyIdentity],
                selectedID: legacyIdentity.stableID
            )
            try saveCollection(collection)
            defaults.removeObject(forKey: metadataKey)
            return collection
        }
        return StoredDirectVoiceIdentities(identities: [], selectedID: nil)
    }

    nonisolated private func saveCollection(_ collection: StoredDirectVoiceIdentities) throws {
        defaults.set(try JSONEncoder().encode(collection), forKey: collectionKey)
    }

    nonisolated private func loadOrCreatePrivateKey(callsign: String) throws -> Curve25519.Signing.PrivateKey {
        let normalized = try Self.normalizeCallsign(callsign)
        if let data = try secretStore.load(account: keyAccount(callsign: normalized)) {
            guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else {
                throw DirectVoiceIdentityError.missingPrivateKey
            }
            return key
        }
        if let migrated = try migrateLegacyKey(callsign: normalized) {
            return migrated
        }
        let key = Curve25519.Signing.PrivateKey()
        try secretStore.save(
            key.rawRepresentation,
            account: keyAccount(callsign: normalized),
            afterFirstUnlock: false
        )
        return key
    }

    nonisolated private func loadPrivateKey(
        callsign: String,
        allowingLegacyMigration: Bool
    ) throws -> Curve25519.Signing.PrivateKey {
        let normalized = try Self.normalizeCallsign(callsign)
        if let data = try secretStore.load(account: keyAccount(callsign: normalized)) {
            guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else {
                throw DirectVoiceIdentityError.missingPrivateKey
            }
            return key
        }
        if allowingLegacyMigration, let migrated = try migrateLegacyKey(callsign: normalized) {
            return migrated
        }
        throw DirectVoiceIdentityError.missingPrivateKey
    }

    nonisolated private func migrateLegacyKey(
        callsign: String
    ) throws -> Curve25519.Signing.PrivateKey? {
        let collection = try loadCollection()
        guard collection.identities.contains(where: { $0.callsign == callsign }),
              let data = try secretStore.load(account: legacyAccount),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else {
            return nil
        }
        try secretStore.save(
            data,
            account: keyAccount(callsign: callsign),
            afterFirstUnlock: false
        )
        try secretStore.remove(account: legacyAccount)
        return key
    }

    nonisolated private func keyAccount(callsign: String) -> String {
        let digest = Data(SHA256.hash(data: Data(callsign.utf8)))
        return "ed25519-seed.\(FMOV4Base64URL.encode(digest))"
    }

    nonisolated static func normalizeCallsign(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty, normalized.utf8.count <= 12,
              normalized.utf8.allSatisfy({ byte in
                  (48 ... 57).contains(byte) || (65 ... 90).contains(byte) || byte == 45
              }) else { throw DirectVoiceIdentityError.invalidCallsign }
        return normalized
    }
}

private nonisolated struct StoredDirectVoiceIdentities: Codable {
    var identities: [DirectVoiceIdentity]
    var selectedID: String?
}

private nonisolated struct SignedIdentityBundle: Decodable {
    let rootCert: RootCertificateJSON
    let intermediateCert: IntermediateCertificateJSON
    let userCert: UserCertificateJSON

    func normalizedCallsign() throws -> String {
        try KeychainDirectVoiceIdentityProvider.normalizeCallsign(userCert.subject.callsign)
    }

    func verifiedIdentity(publicKey: Data, callsign: String, now: Date) throws -> DirectVoiceIdentity {
        let nowSeconds = UInt64(now.timeIntervalSince1970)
        guard userCert.subject.publicKeyData == publicKey else {
            throw DirectVoiceIdentityError.publicKeyMismatch
        }
        guard userCert.issuerSn == intermediateCert.sn,
              intermediateCert.extensions.uidRange.start ... intermediateCert.extensions.uidRange.end ~= userCert.subject.uid,
              rootCert.sn == intermediateCert.issuer.sn,
              rootCert.subject.publicKeyData == intermediateCert.issuer.publicKeyData else {
            throw DirectVoiceIdentityError.invalidBundle
        }
        guard rootCert.iat <= nowSeconds, nowSeconds < rootCert.exp,
              intermediateCert.iat <= nowSeconds, nowSeconds < intermediateCert.exp,
              userCert.iat <= nowSeconds, nowSeconds < userCert.exp else {
            throw DirectVoiceIdentityError.certificateExpired
        }
        guard rootCert.verifySelf(), intermediateCert.verify(using: rootCert), userCert.verify(using: intermediateCert) else {
            throw DirectVoiceIdentityError.invalidCertificateSignature
        }
        guard let uid = UInt32(exactly: userCert.subject.uid) else {
            throw DirectVoiceIdentityError.invalidBundle
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return DirectVoiceIdentity(
            callsign: callsign,
            uid: uid,
            issuedAt: userCert.iat,
            expiresAt: userCert.exp,
            issuerSerialNumber: userCert.issuerSn,
            rootFingerprint: Data(SHA256.hash(data: try rootCert.tbsData())),
            intermediateCertificateJSON: try encoder.encode(intermediateCert),
            userCertificateJSON: try encoder.encode(userCert)
        )
    }
}

private nonisolated struct RootCertificateJSON: Codable {
    struct Issuer: Codable { let name: String; let email: String }
    struct Subject: Codable { let name: String; let publicKey: String }
    struct Extensions: Codable {
        let isCA: Bool
        let pathLen: UInt64
        let crl: String
        let license: String
        let keyId: String
    }
    let sn: UInt64
    let type: String
    let issuer: Issuer
    let subject: Subject
    let extensions: Extensions
    let iat: UInt64
    let exp: UInt64
    let signatureAlgorithm: String
    let signature: String

    func tbsData() throws -> Data {
        try DeterministicCBOR().encode(.array([
            .text("FMO"), .unsigned(4), .text("rootCA"), .unsigned(sn),
            .text(issuer.name), .text(issuer.email), .text(subject.name), .bytes(subject.publicKeyData),
            .boolean(extensions.isCA), .unsigned(extensions.pathLen), .text(extensions.crl),
            .text(extensions.license), .text(extensions.keyId), .unsigned(iat), .unsigned(exp),
        ]))
    }

    func verifySelf() -> Bool {
        guard type == "rootCA", signatureAlgorithm == "Ed25519", extensions.isCA,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: subject.publicKeyData),
              let signatureData = try? FMOV4Base64URL.decode(signature, requiredByteCount: 64),
              let tbs = try? tbsData() else { return false }
        return key.isValidSignature(signatureData, for: tbs)
    }
}

private nonisolated struct IntermediateCertificateJSON: Codable {
    struct Issuer: Codable { let sn: UInt64; let name: String; let publicKey: String }
    struct Subject: Codable { let name: String; let email: String; let publicKey: String }
    struct UIDRange: Codable { let start: UInt64; let end: UInt64 }
    struct Extensions: Codable {
        let isCA: Bool
        let pathLen: UInt64
        let keyId: String
        let crl: String
        let license: String
        let uidRange: UIDRange
        let issuingCountries: [String]
    }
    let sn: UInt64
    let type: String
    let issuer: Issuer
    let subject: Subject
    let extensions: Extensions
    let iat: UInt64
    let exp: UInt64
    let signatureAlgorithm: String
    let signature: String

    func tbsData() throws -> Data {
        try DeterministicCBOR().encode(.array([
            .text("FMO"), .unsigned(4), .text("intermediateCA"), .unsigned(sn),
            .unsigned(issuer.sn), .text(issuer.name), .bytes(issuer.publicKeyData),
            .text(subject.name), .text(subject.email), .bytes(subject.publicKeyData),
            .boolean(extensions.isCA), .unsigned(extensions.pathLen), .text(extensions.keyId),
            .text(extensions.crl), .text(extensions.license), .unsigned(extensions.uidRange.start),
            .unsigned(extensions.uidRange.end),
            .array(extensions.issuingCountries.sorted().map(DeterministicCBORValue.text)),
            .unsigned(iat), .unsigned(exp),
        ]))
    }

    func verify(using root: RootCertificateJSON) -> Bool {
        guard type == "intermediateCA", signatureAlgorithm == "Ed25519", extensions.isCA,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: root.subject.publicKeyData),
              let signatureData = try? FMOV4Base64URL.decode(signature, requiredByteCount: 64),
              let tbs = try? tbsData() else { return false }
        return key.isValidSignature(signatureData, for: tbs)
    }
}

private nonisolated struct UserCertificateJSON: Codable {
    struct Subject: Codable { let callsign: String; let uid: UInt64; let publicKey: String }
    let type: String
    let certFingerprint: String?
    let issuerSn: UInt64
    let subject: Subject
    let iat: UInt64
    let exp: UInt64
    let signatureAlgorithm: String
    let signature: String

    func tbsData() throws -> Data {
        try DeterministicCBOR().encode(.array([
            .text("FMO"), .unsigned(4), .text("userCert"), .unsigned(issuerSn),
            .text(subject.callsign.uppercased()), .unsigned(subject.uid), .bytes(subject.publicKeyData),
            .unsigned(iat), .unsigned(exp),
        ]))
    }

    func verify(using issuer: IntermediateCertificateJSON) -> Bool {
        guard type == "userCert", signatureAlgorithm == "Ed25519",
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: issuer.subject.publicKeyData),
              let signatureData = try? FMOV4Base64URL.decode(signature, requiredByteCount: 64),
              let tbs = try? tbsData() else { return false }
        return key.isValidSignature(signatureData, for: tbs)
    }
}

private nonisolated extension RootCertificateJSON.Subject {
    var publicKeyData: Data { (try? FMOV4Base64URL.decode(publicKey, requiredByteCount: 32)) ?? Data() }
}

private nonisolated extension IntermediateCertificateJSON.Issuer {
    var publicKeyData: Data { (try? FMOV4Base64URL.decode(publicKey, requiredByteCount: 32)) ?? Data() }
}

private nonisolated extension IntermediateCertificateJSON.Subject {
    var publicKeyData: Data { (try? FMOV4Base64URL.decode(publicKey, requiredByteCount: 32)) ?? Data() }
}

private nonisolated extension UserCertificateJSON.Subject {
    var publicKeyData: Data { (try? FMOV4Base64URL.decode(publicKey, requiredByteCount: 32)) ?? Data() }
}
