import CryptoKit
import Foundation
import Testing
@testable import FMOc

struct FMOV4TrustTests {
    @Test
    func bundledOfficialChainVerifiesAndHasExpectedLifetime() throws {
        let material = FMOV4TrustMaterial.official
        let root = try #require(material.roots[1])
        let intermediate = try #require(material.intermediates[1_001])

        #expect(root.verifySelfSignature())
        #expect(intermediate.verify(using: root))
        #expect(root.expiresAt == 2_095_505_415)
        #expect(intermediate.expiresAt == 1_937_652_834)
    }

    @Test
    func emptyOfficialCRLsMeanNoKnownRevocations() async throws {
        let material = FMOV4TrustMaterial.official
        let root = try #require(material.roots[1])
        let intermediate = try #require(material.intermediates[1_001])
        let user = FMOV4UserCertificate(
            issuerSerialNumber: intermediate.serialNumber,
            callsign: "BG0TST",
            uid: 42,
            publicKey: Data(repeating: 1, count: 32),
            issuedAt: 1,
            expiresAt: 2,
            caSignature: Data(repeating: 2, count: 64),
            blob: Data([0x80])
        )
        let store = OfficialFMOV4CRLStore(httpClient: EmptyObjectHTTPClient())

        let result = await store.check(
            user: user,
            intermediate: intermediate,
            root: root,
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(result == .clear(root: .notPublished, intermediate: .notPublished))
    }

    @Test
    func malformedCRLIsRejectedInsteadOfReportedAsNetworkUnavailable() async throws {
        let material = FMOV4TrustMaterial.official
        let root = try #require(material.roots[1])
        let intermediate = try #require(material.intermediates[1_001])
        let user = FMOV4UserCertificate(
            issuerSerialNumber: intermediate.serialNumber,
            callsign: "BG0TST",
            uid: 42,
            publicKey: Data(repeating: 1, count: 32),
            issuedAt: 1,
            expiresAt: 2,
            caSignature: Data(repeating: 2, count: 64),
            blob: Data([0x80])
        )
        let store = OfficialFMOV4CRLStore(httpClient: MalformedHTTPClient())

        let result = await store.check(
            user: user,
            intermediate: intermediate,
            root: root,
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(result == .invalidCRL)
    }

    @Test
    func verifiesSyntheticCertificateChainAndSignedActivityFrame() async throws {
        let fixture = try SignedFMOV4Fixture()
        let verifier = FMOV4Verifier(
            trustMaterial: fixture.trustMaterial,
            revocationChecker: ClearRevocationChecker()
        )

        let result = await verifier.verify(fixture.frame, at: fixture.date)

        guard case .accepted(let authenticated) = result else {
            Issue.record("Expected a fully authenticated FMO V4 frame, got \(result)")
            return
        }
        #expect(authenticated.source.formatted == "BG0TST-10")
        #expect(abs(authenticated.latitude - 22.557333333333332) < 0.000_000_1)
        #expect(abs(authenticated.longitude - 113.92766666666667) < 0.000_000_1)
        #expect(authenticated.trustLevel == .trusted)
        #expect(authenticated.verifiedTimeSalt == fixture.timeSalt)
    }

    @Test
    func networkStoreDeduplicatesARepeatedAuthenticatedFrame() async throws {
        let fixture = try SignedFMOV4Fixture()
        let verifier = FMOV4Verifier(
            trustMaterial: fixture.trustMaterial,
            revocationChecker: ClearRevocationChecker()
        )
        let store = FMOV4NetworkStore(verifier: verifier)

        _ = await store.process(.position(fixture.frame), at: fixture.date)
        let snapshot = await store.process(.position(fixture.frame), at: fixture.date)

        #expect(snapshot.stations.count == 1)
        #expect(snapshot.events.count == 1)
        #expect(snapshot.events.first?.kind == .vocal)
        #expect(snapshot.events.first?.callsign == "BG0TST")
    }

    @Test
    func networkStoreRetentionLimitsEventAgeAndCount() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let policy = FMOV4NetworkStore.Policy(
            maximumEvents: 2,
            eventLifetime: 60 * 60
        )
        let events = [
            makeEvent(id: "newest", observedAt: now),
            makeEvent(id: "recent", observedAt: now.addingTimeInterval(-30 * 60)),
            makeEvent(id: "overflow", observedAt: now.addingTimeInterval(-45 * 60)),
            makeEvent(id: "expired", observedAt: now.addingTimeInterval(-2 * 60 * 60)),
        ]

        let retained = FMOV4NetworkStore.retainedEvents(events, at: now, policy: policy)

        #expect(retained.map(\.id) == ["newest", "recent"])
    }

    private func makeEvent(id: String, observedAt: Date) -> FMOV4NetworkEvent {
        FMOV4NetworkEvent(
            id: id,
            kind: .cq,
            callsign: "BG0TST",
            ssid: 10,
            latitude: 31.2304,
            longitude: 121.4737,
            serverUID: nil,
            topic: nil,
            content: nil,
            observedAt: observedAt,
            trustLevel: .trusted
        )
    }
}

private nonisolated struct EmptyObjectHTTPClient: FMOV4HTTPFetching {
    func data(from url: URL) async throws -> Data { Data("{}".utf8) }
}

private nonisolated struct MalformedHTTPClient: FMOV4HTTPFetching {
    func data(from url: URL) async throws -> Data { Data("{\"type\":\"rootCRL\"}".utf8) }
}

private actor ClearRevocationChecker: FMOV4RevocationChecking {
    func check(
        user: FMOV4UserCertificate,
        intermediate: FMOV4IntermediateCertificate,
        root: FMOV4RootCertificate,
        at date: Date
    ) -> FMOV4RevocationResult {
        .clear(
            root: .current(number: 1, nextUpdate: date.addingTimeInterval(3_600)),
            intermediate: .notPublished
        )
    }
}

private nonisolated struct SignedFMOV4Fixture {
    let trustMaterial: FMOV4TrustMaterial
    let frame: UnverifiedFMOV4PositionFrame
    let date = Date(timeIntervalSince1970: 2_000_000_000)
    let timeSalt: UInt64 = 2_000_000_000 / 600

    init() throws {
        let rootKey = Curve25519.Signing.PrivateKey()
        let intermediateKey = Curve25519.Signing.PrivateKey()
        let userKey = Curve25519.Signing.PrivateKey()
        let rootURL = URL(string: "https://example.invalid/root-crl.json")!
        let intermediateURL = URL(string: "https://example.invalid/intermediate-crl.json")!
        let licenseURL = URL(string: "https://example.invalid/license")!

        let unsignedRoot = FMOV4RootCertificate(
            serialNumber: 1,
            issuerName: "Test Root",
            issuerEmail: "root@example.invalid",
            subjectName: "Test Root",
            publicKey: rootKey.publicKey.rawRepresentation,
            pathLength: 1,
            crlURL: rootURL,
            licenseURL: licenseURL,
            keyID: "test-root",
            issuedAt: 1_900_000_000,
            expiresAt: 2_100_000_000,
            signature: Data(repeating: 0, count: 64)
        )
        let root = FMOV4RootCertificate(
            serialNumber: unsignedRoot.serialNumber,
            issuerName: unsignedRoot.issuerName,
            issuerEmail: unsignedRoot.issuerEmail,
            subjectName: unsignedRoot.subjectName,
            publicKey: unsignedRoot.publicKey,
            pathLength: unsignedRoot.pathLength,
            crlURL: unsignedRoot.crlURL,
            licenseURL: unsignedRoot.licenseURL,
            keyID: unsignedRoot.keyID,
            issuedAt: unsignedRoot.issuedAt,
            expiresAt: unsignedRoot.expiresAt,
            signature: try rootKey.signature(for: unsignedRoot.tbsData())
        )

        let unsignedIntermediate = FMOV4IntermediateCertificate(
            serialNumber: 1_001,
            issuerSerialNumber: root.serialNumber,
            issuerName: root.subjectName,
            issuerPublicKey: root.publicKey,
            subjectName: "Test Intermediate",
            subjectEmail: "intermediate@example.invalid",
            publicKey: intermediateKey.publicKey.rawRepresentation,
            pathLength: 0,
            keyID: "test-intermediate",
            crlURL: intermediateURL,
            licenseURL: licenseURL,
            uidRange: 1 ... 1_000,
            issuingCountries: ["CN"],
            issuedAt: 1_900_000_000,
            expiresAt: 2_050_000_000,
            signature: Data(repeating: 0, count: 64)
        )
        let intermediate = FMOV4IntermediateCertificate(
            serialNumber: unsignedIntermediate.serialNumber,
            issuerSerialNumber: unsignedIntermediate.issuerSerialNumber,
            issuerName: unsignedIntermediate.issuerName,
            issuerPublicKey: unsignedIntermediate.issuerPublicKey,
            subjectName: unsignedIntermediate.subjectName,
            subjectEmail: unsignedIntermediate.subjectEmail,
            publicKey: unsignedIntermediate.publicKey,
            pathLength: unsignedIntermediate.pathLength,
            keyID: unsignedIntermediate.keyID,
            crlURL: unsignedIntermediate.crlURL,
            licenseURL: unsignedIntermediate.licenseURL,
            uidRange: unsignedIntermediate.uidRange,
            issuingCountries: unsignedIntermediate.issuingCountries,
            issuedAt: unsignedIntermediate.issuedAt,
            expiresAt: unsignedIntermediate.expiresAt,
            signature: try rootKey.signature(for: unsignedIntermediate.tbsData())
        )

        let userTBS: [DeterministicCBORValue] = [
            .text("FMO"), .unsigned(4), .text("userCert"),
            .unsigned(intermediate.serialNumber), .text("BG0TST"), .unsigned(42),
            .bytes(userKey.publicKey.rawRepresentation),
            .unsigned(1_950_000_000), .unsigned(2_020_000_000),
        ]
        let encodedUserTBS = try DeterministicCBOR().encode(.array(userTBS))
        let userSignature = try intermediateKey.signature(for: encodedUserTBS)
        let certificateBlob = try DeterministicCBOR().encode(
            .array(userTBS + [.bytes(userSignature)])
        )
        let certificate = try FMOV4UserCertificateDecoder().decode(certificateBlob)

        let source = TNC2Address(callsign: "BG0TST", ssid: 10)
        let latitudeText = "2233.44N"
        let longitudeText = "11355.66E"
        let activity = FMOV4Activity(type: .vocal, serverUID: 123)
        let messageTBS: [DeterministicCBORValue] = [
            .text("FMO"), .unsigned(4), .text("VOCAL"),
            .text(source.callsign), .unsigned(UInt64(source.ssid)),
            .text(latitudeText), .text(longitudeText), .bytes(certificate.blobHash),
            .unsigned(activity.serverUID), .unsigned(timeSalt),
        ]
        let messageSignature = try userKey.signature(
            for: DeterministicCBOR().encode(.array(messageTBS))
        )

        trustMaterial = FMOV4TrustMaterial(roots: [root], intermediates: [intermediate])
        frame = UnverifiedFMOV4PositionFrame(
            source: source,
            latitudeText: latitudeText,
            longitudeText: longitudeText,
            symbolTable: "/",
            symbolCode: "I",
            certificateBlob: certificateBlob,
            signature: messageSignature,
            body: .activity(activity)
        )
    }
}
