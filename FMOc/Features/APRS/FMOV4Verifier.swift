import CryptoKit
import Foundation

nonisolated enum FMOV4VerificationFailure: Equatable, Hashable, Sendable {
    case malformedCertificate
    case callsignMismatch
    case unknownIssuer
    case invalidRoot
    case invalidIntermediate
    case invalidUserCertificate
    case rootExpired
    case intermediateExpired
    case userCertificateExpired
    case uidOutOfRange
    case countryNotAllowed
    case revoked
    case invalidCRL
    case invalidMessageSignature
}

nonisolated enum FMOV4TrustLevel: Equatable, Sendable {
    case trusted
    case revocationStale
    case revocationUnavailable
}

nonisolated struct AuthenticatedFMOV4PositionFrame: Equatable, Sendable {
    let source: TNC2Address
    let latitude: Double
    let longitude: Double
    let certificate: FMOV4UserCertificate
    let body: FMOV4PositionBody
    let trustLevel: FMOV4TrustLevel
    let rootCRL: FMOV4CRLFreshness
    let intermediateCRL: FMOV4CRLFreshness
    let verifiedAt: Date
    let verifiedTimeSalt: UInt64
}

nonisolated enum FMOV4VerificationResult: Equatable, Sendable {
    case accepted(AuthenticatedFMOV4PositionFrame)
    case rejected(FMOV4VerificationFailure)
}

actor FMOV4Verifier {
    private let trustMaterial: FMOV4TrustMaterial
    private let revocationChecker: any FMOV4RevocationChecking
    private let certificateDecoder = FMOV4UserCertificateDecoder()

    init(
        trustMaterial: FMOV4TrustMaterial = .official,
        revocationChecker: any FMOV4RevocationChecking
    ) {
        self.trustMaterial = trustMaterial
        self.revocationChecker = revocationChecker
    }

    func verify(
        _ frame: UnverifiedFMOV4PositionFrame,
        at date: Date
    ) async -> FMOV4VerificationResult {
        let certificate: FMOV4UserCertificate
        do {
            certificate = try certificateDecoder.decode(frame.certificateBlob)
        } catch {
            return .rejected(.malformedCertificate)
        }

        guard certificate.callsign == frame.source.callsign else {
            return .rejected(.callsignMismatch)
        }
        guard let intermediate = trustMaterial.intermediates[certificate.issuerSerialNumber] else {
            return .rejected(.unknownIssuer)
        }
        guard let root = trustMaterial.roots[intermediate.issuerSerialNumber] else {
            return .rejected(.unknownIssuer)
        }

        let unixTime = UInt64(max(0, date.timeIntervalSince1970.rounded(.down)))
        guard root.verifySelfSignature() else { return .rejected(.invalidRoot) }
        guard root.isValid(at: unixTime) else { return .rejected(.rootExpired) }
        guard intermediate.verify(using: root) else { return .rejected(.invalidIntermediate) }
        guard intermediate.isValid(at: unixTime) else { return .rejected(.intermediateExpired) }
        guard intermediate.uidRange.contains(certificate.uid) else {
            return .rejected(.uidOutOfRange)
        }
        guard certificate.verify(using: intermediate) else {
            return .rejected(.invalidUserCertificate)
        }
        guard certificate.isValid(at: unixTime) else {
            return .rejected(.userCertificateExpired)
        }

        if case .station(let station) = frame.body,
           !intermediate.issuingCountries.contains(station.countryCode) {
            return .rejected(.countryNotAllowed)
        }

        let revocation = await revocationChecker.check(
            user: certificate,
            intermediate: intermediate,
            root: root,
            at: date
        )
        let rootCRL: FMOV4CRLFreshness
        let intermediateCRL: FMOV4CRLFreshness
        switch revocation {
        case .revoked:
            return .rejected(.revoked)
        case .invalidCRL:
            return .rejected(.invalidCRL)
        case .clear(let root, let intermediate):
            rootCRL = root
            intermediateCRL = intermediate
        }

        guard let verifiedTimeSalt = verifyMessageSignature(
            frame,
            certificate: certificate,
            now: unixTime
        ) else {
            return .rejected(.invalidMessageSignature)
        }
        guard
            let latitude = Self.latitude(from: frame.latitudeText),
            let longitude = Self.longitude(from: frame.longitudeText)
        else {
            return .rejected(.invalidMessageSignature)
        }

        return .accepted(
            AuthenticatedFMOV4PositionFrame(
                source: frame.source,
                latitude: latitude,
                longitude: longitude,
                certificate: certificate,
                body: frame.body,
                trustLevel: Self.trustLevel(root: rootCRL, intermediate: intermediateCRL),
                rootCRL: rootCRL,
                intermediateCRL: intermediateCRL,
                verifiedAt: date,
                verifiedTimeSalt: verifiedTimeSalt
            )
        )
    }

    private func verifyMessageSignature(
        _ frame: UnverifiedFMOV4PositionFrame,
        certificate: FMOV4UserCertificate,
        now: UInt64
    ) -> UInt64? {
        guard
            let publicKey = try? Curve25519.Signing.PublicKey(
                rawRepresentation: certificate.publicKey
            )
        else {
            return nil
        }
        let currentSalt = now / 600
        var candidates = [currentSalt]
        if currentSalt > 0 { candidates.append(currentSalt - 1) }
        candidates.append(currentSalt + 1)

        for salt in candidates {
            guard let tbs = try? messageTBS(frame, certificate: certificate, timeSalt: salt) else {
                continue
            }
            if publicKey.isValidSignature(frame.signature, for: tbs) {
                return salt
            }
        }
        return nil
    }

    private func messageTBS(
        _ frame: UnverifiedFMOV4PositionFrame,
        certificate: FMOV4UserCertificate,
        timeSalt: UInt64
    ) throws -> Data {
        var values: [DeterministicCBORValue] = [
            .text("FMO"), .unsigned(4),
        ]
        let common: [DeterministicCBORValue] = [
            .text(frame.source.callsign), .unsigned(UInt64(frame.source.ssid)),
            .text(frame.latitudeText), .text(frame.longitudeText), .bytes(certificate.blobHash),
        ]

        switch frame.body {
        case .activity(let activity):
            values.append(.text(activity.type.rawValue))
            values.append(contentsOf: common)
            values.append(.unsigned(activity.serverUID))
        case .beacon(let beacon):
            values.append(.text("BEACON"))
            values.append(contentsOf: common)
            values.append(.text(beacon.frequency))
            if let height = beacon.antennaHeight { values.append(.unsigned(UInt64(height))) }
            if let rig = beacon.rigName { values.append(.text(rig)) }
            if let antenna = beacon.antennaName { values.append(.text(antenna)) }
        case .station(let station):
            values.append(.text("STATION"))
            values.append(contentsOf: common)
            values.append(contentsOf: [
                .text(station.countryCode), .text(station.name), .text(station.host),
                .unsigned(UInt64(station.port)), .unsigned(UInt64(station.filterKilometers)),
                .unsigned(UInt64(station.onlineUserCount)), .unsigned(UInt64(station.peakUserCount)),
            ])
        case .joint(let statusHash):
            values.append(.text("JOINT"))
            values.append(contentsOf: common)
            values.append(.bytes(statusHash))
        }
        values.append(.unsigned(timeSalt))
        return try DeterministicCBOR().encode(.array(values))
    }

    private static func trustLevel(
        root: FMOV4CRLFreshness,
        intermediate: FMOV4CRLFreshness
    ) -> FMOV4TrustLevel {
        let values = [root, intermediate]
        if values.contains(where: {
            if case .unavailable = $0 { return true }
            return false
        }) {
            return .revocationUnavailable
        }
        if values.contains(where: {
            if case .stale = $0 { return true }
            return false
        }) {
            return .revocationStale
        }
        return .trusted
    }

    private static func latitude(from value: String) -> Double? {
        guard value.count == 8 else { return nil }
        let degreesText = value.prefix(2)
        let minutesText = value.dropFirst(2).dropLast()
        guard let degrees = Double(degreesText), let minutes = Double(minutesText) else { return nil }
        let sign = value.last == "S" ? -1.0 : 1.0
        return sign * (degrees + minutes / 60)
    }

    private static func longitude(from value: String) -> Double? {
        guard value.count == 9 else { return nil }
        let degreesText = value.prefix(3)
        let minutesText = value.dropFirst(3).dropLast()
        guard let degrees = Double(degreesText), let minutes = Double(minutesText) else { return nil }
        let sign = value.last == "W" ? -1.0 : 1.0
        return sign * (degrees + minutes / 60)
    }
}
