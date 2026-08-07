import Foundation
import Security

nonisolated enum FmoRemoteSecretStoreError: Error, Equatable, Sendable {
    case keychainFailure(OSStatus)
    case invalidData
}

protocol FmoRemoteSecretStoring: Sendable {
    func load(for target: TNC2Address) async throws -> String?
    func save(_ secret: String, for target: TNC2Address) async throws
    func remove(for target: TNC2Address) async throws
}

actor KeychainFmoRemoteSecretStore: FmoRemoteSecretStoring {
    private let service: String

    init(service: String = "com.bi8syn.FMOc.remote-control") {
        self.service = service
    }

    func load(for target: TNC2Address) throws -> String? {
        var query = baseQuery(for: target)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw FmoRemoteSecretStoreError.keychainFailure(status)
        }
        guard
            let data = result as? Data,
            let secret = String(data: data, encoding: .utf8),
            Self.isValid(secret)
        else {
            throw FmoRemoteSecretStoreError.invalidData
        }
        return secret
    }

    func save(_ secret: String, for target: TNC2Address) throws {
        guard Self.isValid(secret) else {
            throw FmoRemoteSecretStoreError.invalidData
        }
        let query = baseQuery(for: target)
        let attributes = [kSecValueData as String: Data(secret.utf8)]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insertion = query
            insertion[kSecValueData as String] = Data(secret.utf8)
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(insertion as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw FmoRemoteSecretStoreError.keychainFailure(status)
            }
        } else if updateStatus != errSecSuccess {
            throw FmoRemoteSecretStoreError.keychainFailure(updateStatus)
        }
    }

    func remove(for target: TNC2Address) throws {
        let status = SecItemDelete(baseQuery(for: target) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FmoRemoteSecretStoreError.keychainFailure(status)
        }
    }

    private func baseQuery(for target: TNC2Address) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: target.formatted,
        ]
    }

    nonisolated private static func isValid(_ secret: String) -> Bool {
        secret.utf8.count == 12 && secret.utf8.allSatisfy { byte in
            (48 ... 57).contains(byte) || (65 ... 90).contains(byte)
        }
    }
}
