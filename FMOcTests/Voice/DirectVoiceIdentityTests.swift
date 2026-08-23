import CryptoKit
import Foundation
import Testing
@testable import FMOc

struct DirectVoiceIdentityTests {
    @Test func importsAValidAppOwnedCertificateChainBoundToKeychainKey() async throws {
        let suiteName = "DirectVoiceIdentityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let provider = KeychainDirectVoiceIdentityProvider(
            service: "com.bi8syn.FMOc.tests.\(UUID().uuidString)",
            defaults: defaults,
            secretStore: InMemoryDirectVoiceSecretStore()
        )
        let enrollment = try provider.enrollmentRequest(callsign: "bi8syn")
        let userPublicKey = try FMOV4Base64URL.decode(enrollment.publicKeyBase64URL, requiredByteCount: 32)
        let rootKey = Curve25519.Signing.PrivateKey()
        let intermediateKey = Curve25519.Signing.PrivateKey()
        let issuedAt: UInt64 = 1_700_000_000
        let expiresAt: UInt64 = 2_000_000_000

        let rootTBS = try DeterministicCBOR().encode(.array([
            .text("FMO"), .unsigned(4), .text("rootCA"), .unsigned(1),
            .text("TESTROOT"), .text("root@example.invalid"), .text("TESTROOT"),
            .bytes(rootKey.publicKey.rawRepresentation), .boolean(true), .unsigned(1),
            .text("https://example.invalid/root.crl"), .text("https://example.invalid/license"),
            .text("root-key"), .unsigned(issuedAt), .unsigned(expiresAt),
        ]))
        let root: [String: Any] = [
            "sn": 1, "type": "rootCA",
            "issuer": ["name": "TESTROOT", "email": "root@example.invalid"],
            "subject": ["name": "TESTROOT", "publicKey": FMOV4Base64URL.encode(rootKey.publicKey.rawRepresentation)],
            "extensions": [
                "isCA": true, "pathLen": 1, "crl": "https://example.invalid/root.crl",
                "license": "https://example.invalid/license", "keyId": "root-key",
            ],
            "iat": issuedAt, "exp": expiresAt, "signatureAlgorithm": "Ed25519",
            "signature": FMOV4Base64URL.encode(try rootKey.signature(for: rootTBS)),
        ]

        let intermediateTBS = try DeterministicCBOR().encode(.array([
            .text("FMO"), .unsigned(4), .text("intermediateCA"), .unsigned(1_001),
            .unsigned(1), .text("TESTROOT"), .bytes(rootKey.publicKey.rawRepresentation),
            .text("TESTINT"), .text("int@example.invalid"), .bytes(intermediateKey.publicKey.rawRepresentation),
            .boolean(true), .unsigned(0), .text("int-key"),
            .text("https://example.invalid/int.crl"), .text("https://example.invalid/license"),
            .unsigned(1_000_000_000), .unsigned(1_999_999_999), .array([.text("CN")]),
            .unsigned(issuedAt), .unsigned(expiresAt),
        ]))
        let intermediate: [String: Any] = [
            "sn": 1_001, "type": "intermediateCA",
            "issuer": [
                "sn": 1, "name": "TESTROOT",
                "publicKey": FMOV4Base64URL.encode(rootKey.publicKey.rawRepresentation),
            ],
            "subject": [
                "name": "TESTINT", "email": "int@example.invalid",
                "publicKey": FMOV4Base64URL.encode(intermediateKey.publicKey.rawRepresentation),
            ],
            "extensions": [
                "isCA": true, "pathLen": 0, "keyId": "int-key",
                "crl": "https://example.invalid/int.crl", "license": "https://example.invalid/license",
                "uidRange": ["start": 1_000_000_000, "end": 1_999_999_999],
                "issuingCountries": ["CN"],
            ],
            "iat": issuedAt, "exp": expiresAt, "signatureAlgorithm": "Ed25519",
            "signature": FMOV4Base64URL.encode(try rootKey.signature(for: intermediateTBS)),
        ]

        let userTBS = try DeterministicCBOR().encode(.array([
            .text("FMO"), .unsigned(4), .text("userCert"), .unsigned(1_001),
            .text("BI8SYN"), .unsigned(1_000_000_001), .bytes(userPublicKey),
            .unsigned(issuedAt), .unsigned(expiresAt),
        ]))
        let user: [String: Any] = [
            "type": "userCert", "issuerSn": 1_001,
            "subject": [
                "callsign": "BI8SYN", "uid": 1_000_000_001,
                "publicKey": enrollment.publicKeyBase64URL,
            ],
            "iat": issuedAt, "exp": expiresAt, "signatureAlgorithm": "Ed25519",
            "signature": FMOV4Base64URL.encode(try intermediateKey.signature(for: userTBS)),
        ]
        let bundle = try JSONSerialization.data(
            withJSONObject: ["rootCert": root, "intermediateCert": intermediate, "userCert": user]
        )

        let identity = try provider.importSignedBundle(
            bundle,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(identity.callsign == "BI8SYN")
        #expect(identity.uid == 1_000_000_001)
        #expect(identity.rootFingerprint.count == 32)
        #expect(try provider.currentIdentity(now: Date(timeIntervalSince1970: 1_800_000_001)) == identity)
        try provider.removeIdentity()
    }
}

private nonisolated final class InMemoryDirectVoiceSecretStore: DirectVoiceSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func load(account: String) -> Data? {
        lock.withLock { values[account] }
    }

    func save(_ data: Data, account: String, afterFirstUnlock: Bool) {
        lock.withLock { values[account] = data }
    }

    func remove(account: String) {
        lock.withLock { _ = values.removeValue(forKey: account) }
    }
}
