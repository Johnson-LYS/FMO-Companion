import Foundation
import Testing
@testable import FMOc

struct DirectVoiceAuthenticationTests {
    @Test func sasRequestUsesBase64URLJSONAndFreshSignedProof() async throws {
        let identity = DirectVoiceSessionTests.identityForAuthentication
        let profile = DirectVoiceSessionTests.profileForAuthentication
        let capture = SignedPayloadCapture()
        let request = try await SASAuthPayloadBuilder().makeRequest(
            identity: identity,
            profile: profile,
            installSuffix: "abcd1234",
            timestamp: 1_800_000_000,
            signer: { data in
                await capture.record(data)
                return Data(repeating: 0x44, count: 64)
            }
        )

        #expect(request.clientID == "fmoc-ios-1000000001-abcd1234")
        #expect(request.username == "BI8SYN")
        #expect(request.tlsServerName == "mqtt.example.invalid")
        #expect(!request.password.contains("="))
        let passwordData = try FMOV4Base64URL.decode(request.password)
        let object = try #require(JSONSerialization.jsonObject(with: passwordData) as? [String: Any])
        #expect(object["targetUID"] as? Int == 5_001)
        #expect(object["role"] as? String == "user")
        #expect((object["proof"] as? [String: Any])?["signature"] as? String == FMOV4Base64URL.encode(Data(repeating: 0x44, count: 64)))
        #expect(await capture.payload()?.count ?? 0 > 64)
    }
}

struct LibOpusCodecTests {
    @Test func encodesAndDecodesOneFixedFortyMillisecondFrame() async throws {
        let codec = try LibOpusCodec()
        let samples = (0 ..< 320).map { index in
            Int16(sin(Double(index) * 2 * .pi * 440 / 8_000) * 4_000)
        }
        let encoded = try await codec.encode40ms(samples)
        #expect(!encoded.isEmpty)
        #expect(encoded.count < 1_276)
        let decoded = try await codec.decode40ms(encoded)
        #expect(decoded.count == 320)
        #expect(decoded.contains(where: { $0 != 0 }))
        await #expect(throws: FMOAudioCodecError.invalidPCMFrame) {
            try await codec.encode40ms([0, 1])
        }
    }
}

private actor SignedPayloadCapture {
    private var value: Data?
    func record(_ data: Data) { value = data }
    func payload() -> Data? { value }
}

private extension DirectVoiceSessionTests {
    static var identityForAuthentication: DirectVoiceIdentity {
        DirectVoiceIdentity(
            callsign: "BI8SYN", uid: 1_000_000_001, issuedAt: 1_700_000_000,
            expiresAt: 4_102_444_800, issuerSerialNumber: 1_001,
            rootFingerprint: Data(repeating: 0x11, count: 32),
            intermediateCertificateJSON: Data("{\"type\":\"intermediateCA\"}".utf8),
            userCertificateJSON: Data("{\"type\":\"userCert\",\"issuerSn\":1001,\"subject\":{\"callsign\":\"BI8SYN\",\"uid\":1000000001,\"publicKey\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\"},\"iat\":1700000000,\"exp\":4102444800,\"signatureAlgorithm\":\"Ed25519\",\"signature\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\"}".utf8)
        )
    }

    static var profileForAuthentication: FMOServerProfile {
        FMOServerProfile(
            displayName: "Test", dialHost: "mqtt.example.invalid", targetHost: "mqtt.example.invalid",
            mqttPort: 8_883, serverUID: 5_001, serverCallsign: "BG5ESN",
            serverCertificateFingerprint: Data(repeating: 0x22, count: 32)
        )
    }
}
