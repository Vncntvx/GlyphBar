import Foundation
import Security

/// Low-level Keychain wrapper used by `ModuleSecretStore`.
///
/// - service: `"com.wenjiexu.GlyphBar.module"` (shared across all modules; per-module
///   isolation is achieved by prefixing the account with `module.<moduleID>.`).
/// - account: caller-supplied, e.g. `"module.deepseek.deepseek.apiKey"`.
@MainActor
final class KeychainBackend {
    private let service: String

    init(service: String = "com.wenjiexu.GlyphBar.module") {
        self.service = service
    }
    func set(_ value: String?, for account: String) throws {
        if let value {
            try set(value: value, for: account)
        } else {
            delete(account)
        }
    }

    func get(_ account: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func set(value: String, for account: String) throws {
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        // Try to update first; if not present, add.
        let updateAttributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ] as CFDictionary,
            updateAttributes as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainError.osStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.osStatus(updateStatus)
        }
    }

    enum KeychainError: Error {
        case osStatus(OSStatus)
    }
}

/// Per-module secret store backed by Keychain, with a one-shot migration path
/// from the legacy plaintext `SecureStore` (`secure.placeholder.<rawKey>` in
/// UserDefaults).
///
/// Migration is idempotent: it writes to Keychain only if the legacy value exists
/// and Keychain has no entry for the same key. It does **not** delete the legacy
/// plaintext, so a rollback remains possible for one release.
@MainActor
final class ModuleSecretStore: Capability {
    static let declaredKey: CapabilityKey = .secretStore

    private let moduleID: String
    private let backend: KeychainBackend
    private let legacyDefaults: UserDefaults

    init(
        moduleID: String,
        backend: KeychainBackend? = nil,
        legacyDefaults: UserDefaults = .standard
    ) {
        self.moduleID = moduleID
        self.backend = backend ?? KeychainBackend()
        self.legacyDefaults = legacyDefaults
    }

    func setSecret(_ value: String?, for rawKey: String) {
        try? backend.set(value, for: account(for: rawKey))
    }

    /// Keychain first; falls back to legacy plaintext if absent (one-release bridge).
    func secret(for rawKey: String) -> String? {
        if let keychainValue = backend.get(account(for: rawKey)) {
            return keychainValue
        }
        return legacyDefaults.string(forKey: legacyKey(for: rawKey))
    }

    func deleteSecret(for rawKey: String) {
        backend.delete(account(for: rawKey))
    }

    /// Idempotent migration: legacy plaintext → Keychain. Does NOT delete the
    /// legacy entry, so rollback remains possible.
    func migrateFromLegacyPlaintext(
        defaults: UserDefaults = .standard,
        rawKeys: [String]
    ) {
        for rawKey in rawKeys {
            let account = account(for: rawKey)
            if backend.get(account) != nil { continue }
            if let legacy = defaults.string(forKey: legacyKey(for: rawKey)) {
                try? backend.set(legacy, for: account)
            }
        }
    }

    private func account(for rawKey: String) -> String {
        "module.\(moduleID).\(rawKey)"
    }

    private func legacyKey(for rawKey: String) -> String {
        "secure.placeholder.\(rawKey)"
    }
}
