import CryptoKit
import Foundation

nonisolated enum FMOV4CRLFreshness: Equatable, Sendable {
    case current(number: UInt64, nextUpdate: Date)
    case notPublished
    case stale(number: UInt64, nextUpdate: Date)
    case unavailable
}

nonisolated enum FMOV4RevocationResult: Equatable, Sendable {
    case clear(root: FMOV4CRLFreshness, intermediate: FMOV4CRLFreshness)
    case revoked
    case invalidCRL
}

protocol FMOV4RevocationChecking: Actor {
    func check(
        user: FMOV4UserCertificate,
        intermediate: FMOV4IntermediateCertificate,
        root: FMOV4RootCertificate,
        at date: Date
    ) async -> FMOV4RevocationResult
}

protocol FMOV4HTTPFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

nonisolated struct URLSessionFMOV4HTTPClient: FMOV4HTTPFetching {
    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadRevalidatingCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard data.count <= 256 * 1_024 else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        return data
    }
}

actor OfficialFMOV4CRLStore: FMOV4RevocationChecking {
    nonisolated struct Policy: Sendable {
        var refreshInterval: TimeInterval = 4 * 60 * 60
    }

    private nonisolated enum CachedCRL: Sendable {
        case notPublished(checkedAt: Date)
        case root(FMOV4RootCRL, checkedAt: Date)
        case intermediate(FMOV4IntermediateCRL, checkedAt: Date)

        func needsRefresh(at date: Date, interval: TimeInterval) -> Bool {
            let checkedAt: Date
            switch self {
            case .notPublished(let value), .root(_, let value), .intermediate(_, let value):
                checkedAt = value
            }
            return date.timeIntervalSince(checkedAt) >= interval
        }
    }

    private let httpClient: any FMOV4HTTPFetching
    private let policy: Policy
    private var cache: [URL: CachedCRL] = [:]

    init(
        httpClient: any FMOV4HTTPFetching = URLSessionFMOV4HTTPClient(),
        policy: Policy = Policy()
    ) {
        self.httpClient = httpClient
        self.policy = policy
    }

    func check(
        user: FMOV4UserCertificate,
        intermediate: FMOV4IntermediateCertificate,
        root: FMOV4RootCertificate,
        at date: Date
    ) async -> FMOV4RevocationResult {
        async let rootResult = loadRootCRL(for: root, at: date)
        async let intermediateResult = loadIntermediateCRL(for: intermediate, at: date)
        let loadedRoot = await rootResult
        let loadedIntermediate = await intermediateResult

        switch (loadedRoot, loadedIntermediate) {
        case (.invalid, _), (_, .invalid):
            return .invalidCRL
        default:
            break
        }

        if case .value(let crl, _) = loadedRoot,
           crl.isRevoked(serialNumber: intermediate.serialNumber, fingerprint: intermediate.fingerprint) {
            return .revoked
        }
        if case .value(let crl, _) = loadedIntermediate,
           crl.isRevoked(uid: user.uid, fingerprint: user.fingerprint) {
            return .revoked
        }

        return .clear(
            root: loadedRoot.freshness(at: date),
            intermediate: loadedIntermediate.freshness(at: date)
        )
    }

    private func loadRootCRL(
        for root: FMOV4RootCertificate,
        at date: Date
    ) async -> LoadResult<FMOV4RootCRL> {
        if let cached = cache[root.crlURL], !cached.needsRefresh(at: date, interval: policy.refreshInterval) {
            switch cached {
            case .notPublished:
                return .notPublished
            case .root(let crl, _):
                return .value(crl, nextUpdate: crl.nextUpdate)
            case .intermediate:
                return .invalid
            }
        }

        let data: Data
        do {
            data = try await httpClient.data(from: root.crlURL)
        } catch {
            if case .root(let crl, _) = cache[root.crlURL] {
                return .value(crl, nextUpdate: crl.nextUpdate)
            }
            return .unavailable
        }
        if Self.isEmptyObject(data) {
            if case .root(let crl, _) = cache[root.crlURL] {
                return .value(crl, nextUpdate: crl.nextUpdate)
            }
            cache[root.crlURL] = .notPublished(checkedAt: date)
            return .notPublished
        }
        guard
            let crl = try? FMOV4RootCRL.decode(data),
            crl.issuerSerialNumber == root.serialNumber,
            crl.thisUpdate <= date.addingTimeInterval(5 * 60),
            crl.verify(using: root)
        else {
            return .invalid
        }
        if case .root(let cached, _) = cache[root.crlURL], cached.number > crl.number {
            return .value(cached, nextUpdate: cached.nextUpdate)
        }
        cache[root.crlURL] = .root(crl, checkedAt: date)
        return .value(crl, nextUpdate: crl.nextUpdate)
    }

    private func loadIntermediateCRL(
        for intermediate: FMOV4IntermediateCertificate,
        at date: Date
    ) async -> LoadResult<FMOV4IntermediateCRL> {
        if let cached = cache[intermediate.crlURL],
           !cached.needsRefresh(at: date, interval: policy.refreshInterval) {
            switch cached {
            case .notPublished:
                return .notPublished
            case .intermediate(let crl, _):
                return .value(crl, nextUpdate: crl.nextUpdate)
            case .root:
                return .invalid
            }
        }

        let data: Data
        do {
            data = try await httpClient.data(from: intermediate.crlURL)
        } catch {
            if case .intermediate(let crl, _) = cache[intermediate.crlURL] {
                return .value(crl, nextUpdate: crl.nextUpdate)
            }
            return .unavailable
        }
        if Self.isEmptyObject(data) {
            if case .intermediate(let crl, _) = cache[intermediate.crlURL] {
                return .value(crl, nextUpdate: crl.nextUpdate)
            }
            cache[intermediate.crlURL] = .notPublished(checkedAt: date)
            return .notPublished
        }
        guard
            let crl = try? FMOV4IntermediateCRL.decode(data),
            crl.issuerSerialNumber == intermediate.serialNumber,
            crl.thisUpdate <= date.addingTimeInterval(5 * 60),
            crl.verify(using: intermediate)
        else {
            return .invalid
        }
        if case .intermediate(let cached, _) = cache[intermediate.crlURL], cached.number > crl.number {
            return .value(cached, nextUpdate: cached.nextUpdate)
        }
        cache[intermediate.crlURL] = .intermediate(crl, checkedAt: date)
        return .value(crl, nextUpdate: crl.nextUpdate)
    }

    private static func isEmptyObject(_ data: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return false
        }
        return dictionary.isEmpty
    }
}

private nonisolated enum LoadResult<Value: Sendable>: Sendable {
    case value(Value, nextUpdate: Date)
    case notPublished
    case unavailable
    case invalid

    func freshness(at date: Date) -> FMOV4CRLFreshness {
        switch self {
        case .value(let value, let nextUpdate):
            let number: UInt64
            if let root = value as? FMOV4RootCRL {
                number = root.number
            } else if let intermediate = value as? FMOV4IntermediateCRL {
                number = intermediate.number
            } else {
                return .unavailable
            }
            return date <= nextUpdate
                ? .current(number: number, nextUpdate: nextUpdate)
                : .stale(number: number, nextUpdate: nextUpdate)
        case .notPublished:
            return .notPublished
        case .unavailable, .invalid:
            return .unavailable
        }
    }
}

nonisolated struct FMOV4RootCRL: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let serialNumber: UInt64
        let fingerprint: Data
        let revokedAt: UInt64
        let reason: UInt64
    }

    let issuerSerialNumber: UInt64
    let number: UInt64
    let thisUpdate: Date
    let nextUpdate: Date
    let entries: [Entry]
    let signature: Data

    static func decode(_ data: Data) throws -> FMOV4RootCRL {
        let payload = try JSONDecoder().decode(RootPayload.self, from: data)
        guard
            payload.type == "rootCRL",
            payload.signatureAlgorithm == "Ed25519",
            payload.thisUpdate < payload.nextUpdate
        else {
            throw FMOV4TrustMaterialError.invalidCertificate
        }
        return FMOV4RootCRL(
            issuerSerialNumber: payload.issuerSn,
            number: payload.crlNumber,
            thisUpdate: Date(timeIntervalSince1970: TimeInterval(payload.thisUpdate)),
            nextUpdate: Date(timeIntervalSince1970: TimeInterval(payload.nextUpdate)),
            entries: try payload.entries.map {
                Entry(
                    serialNumber: $0.sn,
                    fingerprint: try FMOV4Base64URL.decode($0.certFingerprint, requiredByteCount: 32),
                    revokedAt: $0.revokedAt,
                    reason: $0.reason
                )
            }.sorted(by: Entry.sort),
            signature: try FMOV4Base64URL.decode(payload.signature, requiredByteCount: 64)
        )
    }

    func verify(using root: FMOV4RootCertificate) -> Bool {
        guard
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: root.publicKey),
            let tbs = try? tbsData()
        else { return false }
        return key.isValidSignature(signature, for: tbs)
    }

    func isRevoked(serialNumber: UInt64, fingerprint: Data) -> Bool {
        entries.contains { $0.serialNumber == serialNumber && $0.fingerprint == fingerprint }
    }

    private func tbsData() throws -> Data {
        let values: [DeterministicCBORValue] = [
            .text("FMO"), .unsigned(4), .text("rootCRL"), .unsigned(issuerSerialNumber),
            .unsigned(number), .unsigned(UInt64(thisUpdate.timeIntervalSince1970)),
            .unsigned(UInt64(nextUpdate.timeIntervalSince1970)),
            .array(entries.map {
                .array([
                    .unsigned($0.serialNumber), .bytes($0.fingerprint),
                    .unsigned($0.revokedAt), .unsigned($0.reason),
                ])
            }),
        ]
        return try DeterministicCBOR().encode(.array(values))
    }
}

nonisolated struct FMOV4IntermediateCRL: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let uid: UInt64
        let fingerprint: Data
        let revokedAt: UInt64
        let reason: UInt64
    }

    let issuerSerialNumber: UInt64
    let number: UInt64
    let thisUpdate: Date
    let nextUpdate: Date
    let entries: [Entry]
    let signature: Data

    static func decode(_ data: Data) throws -> FMOV4IntermediateCRL {
        let payload = try JSONDecoder().decode(IntermediatePayload.self, from: data)
        guard
            payload.type == "intermediateCRL",
            payload.signatureAlgorithm == "Ed25519",
            payload.thisUpdate < payload.nextUpdate
        else {
            throw FMOV4TrustMaterialError.invalidCertificate
        }
        return FMOV4IntermediateCRL(
            issuerSerialNumber: payload.issuerSn,
            number: payload.crlNumber,
            thisUpdate: Date(timeIntervalSince1970: TimeInterval(payload.thisUpdate)),
            nextUpdate: Date(timeIntervalSince1970: TimeInterval(payload.nextUpdate)),
            entries: try payload.entries.map {
                Entry(
                    uid: $0.uid,
                    fingerprint: try FMOV4Base64URL.decode($0.certFingerprint, requiredByteCount: 32),
                    revokedAt: $0.revokedAt,
                    reason: $0.reason
                )
            }.sorted(by: Entry.sort),
            signature: try FMOV4Base64URL.decode(payload.signature, requiredByteCount: 64)
        )
    }

    func verify(using issuer: FMOV4IntermediateCertificate) -> Bool {
        guard
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: issuer.publicKey),
            let tbs = try? tbsData()
        else { return false }
        return key.isValidSignature(signature, for: tbs)
    }

    func isRevoked(uid: UInt64, fingerprint: Data) -> Bool {
        entries.contains { $0.uid == uid && $0.fingerprint == fingerprint }
    }

    private func tbsData() throws -> Data {
        let values: [DeterministicCBORValue] = [
            .text("FMO"), .unsigned(4), .text("intermediateCRL"), .unsigned(issuerSerialNumber),
            .unsigned(number), .unsigned(UInt64(thisUpdate.timeIntervalSince1970)),
            .unsigned(UInt64(nextUpdate.timeIntervalSince1970)),
            .array(entries.map {
                .array([
                    .unsigned($0.uid), .bytes($0.fingerprint),
                    .unsigned($0.revokedAt), .unsigned($0.reason),
                ])
            }),
        ]
        return try DeterministicCBOR().encode(.array(values))
    }
}

private nonisolated extension FMOV4RootCRL.Entry {
    static func sort(_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.serialNumber == rhs.serialNumber
            ? lhs.fingerprint.lexicographicallyPrecedes(rhs.fingerprint)
            : lhs.serialNumber < rhs.serialNumber
    }
}

private nonisolated extension FMOV4IntermediateCRL.Entry {
    static func sort(_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.uid == rhs.uid
            ? lhs.fingerprint.lexicographicallyPrecedes(rhs.fingerprint)
            : lhs.uid < rhs.uid
    }
}

private nonisolated struct RootPayload: Decodable {
    struct Entry: Decodable {
        let sn: UInt64
        let certFingerprint: String
        let revokedAt: UInt64
        let reason: UInt64
    }

    let type: String
    let issuerSn: UInt64
    let crlNumber: UInt64
    let thisUpdate: UInt64
    let nextUpdate: UInt64
    let entries: [Entry]
    let signatureAlgorithm: String
    let signature: String
}

private nonisolated struct IntermediatePayload: Decodable {
    struct Entry: Decodable {
        let uid: UInt64
        let certFingerprint: String
        let revokedAt: UInt64
        let reason: UInt64
    }

    let type: String
    let issuerSn: UInt64
    let crlNumber: UInt64
    let thisUpdate: UInt64
    let nextUpdate: UInt64
    let entries: [Entry]
    let signatureAlgorithm: String
    let signature: String
}
