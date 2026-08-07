import CryptoKit
import Foundation

nonisolated enum FMOV4TrustMaterialError: Error, Equatable, Sendable {
    case invalidBase64URL
    case invalidPublicKey
    case invalidSignature
    case invalidCertificate
    case invalidCertificateBlob
    case unsupportedIssuer
}

nonisolated enum FMOV4Base64URL {
    static func decode(_ value: String, requiredByteCount: Int? = nil) throws -> Data {
        guard !value.isEmpty else { throw FMOV4TrustMaterialError.invalidBase64URL }
        let paddingStart = value.firstIndex(of: "=")
        if let paddingStart {
            let padding = value[paddingStart...]
            guard padding.count <= 2, padding.allSatisfy({ $0 == "=" }) else {
                throw FMOV4TrustMaterialError.invalidBase64URL
            }
        }
        let unpadded = paddingStart.map { String(value[..<$0]) } ?? value
        guard
            unpadded.utf8.count % 4 != 1,
            unpadded.utf8.allSatisfy({ byte in
                (48 ... 57).contains(byte)
                    || (65 ... 90).contains(byte)
                    || (97 ... 122).contains(byte)
                    || byte == 45
                    || byte == 95
            })
        else {
            throw FMOV4TrustMaterialError.invalidBase64URL
        }
        let standard = unpadded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = standard + String(repeating: "=", count: (4 - standard.utf8.count % 4) % 4)
        guard let data = Data(base64Encoded: padded) else {
            throw FMOV4TrustMaterialError.invalidBase64URL
        }
        if let requiredByteCount, data.count != requiredByteCount {
            throw FMOV4TrustMaterialError.invalidBase64URL
        }
        return data
    }

    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

nonisolated struct FMOV4RootCertificate: Equatable, Sendable {
    let serialNumber: UInt64
    let issuerName: String
    let issuerEmail: String
    let subjectName: String
    let publicKey: Data
    let pathLength: UInt64
    let crlURL: URL
    let licenseURL: URL
    let keyID: String
    let issuedAt: UInt64
    let expiresAt: UInt64
    let signature: Data

    var tbsValues: [DeterministicCBORValue] {
        [
            .text("FMO"), .unsigned(4), .text("rootCA"), .unsigned(serialNumber),
            .text(issuerName), .text(issuerEmail), .text(subjectName), .bytes(publicKey),
            .boolean(true), .unsigned(pathLength), .text(crlURL.absoluteString),
            .text(licenseURL.absoluteString), .text(keyID), .unsigned(issuedAt), .unsigned(expiresAt),
        ]
    }

    func tbsData() throws -> Data {
        try DeterministicCBOR().encode(.array(tbsValues))
    }

    func verifySelfSignature() -> Bool {
        guard
            publicKey.count == 32,
            signature.count == 64,
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
            let tbs = try? tbsData()
        else {
            return false
        }
        return key.isValidSignature(signature, for: tbs)
    }

    func isValid(at unixTime: UInt64) -> Bool {
        issuedAt <= unixTime && unixTime < expiresAt
    }

    var fingerprint: Data {
        (try? tbsData()).map { Data(SHA256.hash(data: $0)) } ?? Data()
    }
}

nonisolated struct FMOV4IntermediateCertificate: Equatable, Sendable {
    let serialNumber: UInt64
    let issuerSerialNumber: UInt64
    let issuerName: String
    let issuerPublicKey: Data
    let subjectName: String
    let subjectEmail: String
    let publicKey: Data
    let pathLength: UInt64
    let keyID: String
    let crlURL: URL
    let licenseURL: URL
    let uidRange: ClosedRange<UInt64>
    let issuingCountries: [String]
    let issuedAt: UInt64
    let expiresAt: UInt64
    let signature: Data

    var tbsValues: [DeterministicCBORValue] {
        [
            .text("FMO"), .unsigned(4), .text("intermediateCA"),
            .unsigned(serialNumber), .unsigned(issuerSerialNumber), .text(issuerName),
            .bytes(issuerPublicKey), .text(subjectName), .text(subjectEmail), .bytes(publicKey),
            .boolean(true), .unsigned(pathLength), .text(keyID), .text(crlURL.absoluteString),
            .text(licenseURL.absoluteString), .unsigned(uidRange.lowerBound),
            .unsigned(uidRange.upperBound),
            .array(issuingCountries.sorted().map(DeterministicCBORValue.text)),
            .unsigned(issuedAt), .unsigned(expiresAt),
        ]
    }

    func tbsData() throws -> Data {
        try DeterministicCBOR().encode(.array(tbsValues))
    }

    func verify(using root: FMOV4RootCertificate) -> Bool {
        guard
            issuerSerialNumber == root.serialNumber,
            issuerPublicKey == root.publicKey,
            pathLength == 0,
            publicKey.count == 32,
            signature.count == 64,
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: root.publicKey),
            let tbs = try? tbsData()
        else {
            return false
        }
        return key.isValidSignature(signature, for: tbs)
    }

    func isValid(at unixTime: UInt64) -> Bool {
        issuedAt <= unixTime && unixTime < expiresAt
    }

    var fingerprint: Data {
        (try? tbsData()).map { Data(SHA256.hash(data: $0)) } ?? Data()
    }
}

nonisolated struct FMOV4UserCertificate: Equatable, Sendable {
    let issuerSerialNumber: UInt64
    let callsign: String
    let uid: UInt64
    let publicKey: Data
    let issuedAt: UInt64
    let expiresAt: UInt64
    let caSignature: Data
    let blob: Data

    var tbsValues: [DeterministicCBORValue] {
        [
            .text("FMO"), .unsigned(4), .text("userCert"),
            .unsigned(issuerSerialNumber), .text(callsign), .unsigned(uid),
            .bytes(publicKey), .unsigned(issuedAt), .unsigned(expiresAt),
        ]
    }

    func tbsData() throws -> Data {
        try DeterministicCBOR().encode(.array(tbsValues))
    }

    func verify(using issuer: FMOV4IntermediateCertificate) -> Bool {
        guard
            issuer.serialNumber == issuerSerialNumber,
            issuer.uidRange.contains(uid),
            publicKey.count == 32,
            caSignature.count == 64,
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: issuer.publicKey),
            let tbs = try? tbsData()
        else {
            return false
        }
        return key.isValidSignature(caSignature, for: tbs)
    }

    func isValid(at unixTime: UInt64) -> Bool {
        issuedAt <= unixTime && unixTime < expiresAt
    }

    var fingerprint: Data {
        (try? tbsData()).map { Data(SHA256.hash(data: $0)) } ?? Data()
    }

    var blobHash: Data {
        Data(SHA256.hash(data: blob))
    }
}

nonisolated struct FMOV4UserCertificateDecoder: Sendable {
    func decode(_ blob: Data) throws -> FMOV4UserCertificate {
        guard case let .array(values) = try DeterministicCBOR().decode(blob), values.count == 10 else {
            throw FMOV4TrustMaterialError.invalidCertificateBlob
        }
        guard
            values[0].textValue == "FMO",
            values[1].unsignedValue == 4,
            values[2].textValue == "userCert",
            let issuerSerialNumber = values[3].unsignedValue,
            let callsign = values[4].textValue,
            callsign == callsign.uppercased(),
            callsign.utf8.count >= 3,
            callsign.utf8.allSatisfy(Self.isASCIIAlphanumeric),
            let uid = values[5].unsignedValue,
            let publicKey = values[6].bytesValue,
            publicKey.count == 32,
            let issuedAt = values[7].unsignedValue,
            let expiresAt = values[8].unsignedValue,
            issuedAt < expiresAt,
            let caSignature = values[9].bytesValue,
            caSignature.count == 64
        else {
            throw FMOV4TrustMaterialError.invalidCertificateBlob
        }
        return FMOV4UserCertificate(
            issuerSerialNumber: issuerSerialNumber,
            callsign: callsign,
            uid: uid,
            publicKey: publicKey,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            caSignature: caSignature,
            blob: blob
        )
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (48 ... 57).contains(byte) || (65 ... 90).contains(byte)
    }
}

nonisolated struct FMOV4TrustMaterial: Sendable {
    let roots: [UInt64: FMOV4RootCertificate]
    let intermediates: [UInt64: FMOV4IntermediateCertificate]

    init(
        roots: [FMOV4RootCertificate],
        intermediates: [FMOV4IntermediateCertificate]
    ) {
        self.roots = Dictionary(uniqueKeysWithValues: roots.map { ($0.serialNumber, $0) })
        self.intermediates = Dictionary(
            uniqueKeysWithValues: intermediates.map { ($0.serialNumber, $0) }
        )
    }

    static let official: FMOV4TrustMaterial = {
        let rootKey = try! FMOV4Base64URL.decode(
            "DCeeVS320f36ToVP2eOADVN-Q0LzpMYmiVkmNYzuysY",
            requiredByteCount: 32
        )
        let root = FMOV4RootCertificate(
            serialNumber: 1,
            issuerName: "BG5ESN",
            issuerEmail: "xifengzui@yeah.net",
            subjectName: "BG5ESN",
            publicKey: rootKey,
            pathLength: 1,
            crlURL: URL(string: "https://bg5esn.com/share/ca/root_crl.json")!,
            licenseURL: URL(string: "https://bg5esn.com/share/ca/license.md")!,
            keyID: "1",
            issuedAt: 1_779_886_213,
            expiresAt: 2_095_505_415,
            signature: try! FMOV4Base64URL.decode(
                "9QTm906Da0Hf5z2HMdvT02tuYCHyYOcPTNi3Y1Bi-cqpos-Pms_ok7rScAwt2pUSQN34cuKydkyKwdus0N_6CA",
                requiredByteCount: 64
            )
        )
        let intermediate = FMOV4IntermediateCertificate(
            serialNumber: 1_001,
            issuerSerialNumber: 1,
            issuerName: "BG5ESN",
            issuerPublicKey: rootKey,
            subjectName: "BG5ESN",
            subjectEmail: "xifengzui@yeah.net",
            publicKey: try! FMOV4Base64URL.decode(
                "gYPN5agzrKZG2iyEztsVjGD1tVNLozHNm_km7n6OQyk",
                requiredByteCount: 32
            ),
            pathLength: 0,
            keyID: "1",
            crlURL: URL(string: "https://bg5esn.com/share/ca/intermediate_crl.json")!,
            licenseURL: URL(string: "https://bg5esn.com/share/ca/intermediate_license.md")!,
            uidRange: 1 ... 200_000,
            issuingCountries: ["CN"],
            issuedAt: 1_779_886_432,
            expiresAt: 1_937_652_834,
            signature: try! FMOV4Base64URL.decode(
                "d-G7if4xAA5HTe39kT59tGhPY-WjLfXh1PgdpiR_T13zgNVuwHnWLiTORtWLhfW7kF1fN6YGpCpT9FFh0NKFDA",
                requiredByteCount: 64
            )
        )
        precondition(root.verifySelfSignature(), "Bundled FMO Root CA is invalid")
        precondition(intermediate.verify(using: root), "Bundled FMO Intermediate CA is invalid")
        return FMOV4TrustMaterial(roots: [root], intermediates: [intermediate])
    }()
}

private nonisolated extension DeterministicCBORValue {
    var unsignedValue: UInt64? {
        guard case .unsigned(let value) = self else { return nil }
        return value
    }

    var bytesValue: Data? {
        guard case .bytes(let value) = self else { return nil }
        return value
    }

    var textValue: String? {
        guard case .text(let value) = self else { return nil }
        return value
    }
}
