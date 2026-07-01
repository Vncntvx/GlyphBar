import Foundation
import Security

@MainActor
protocol SecretStoreBackend: AnyObject {
    func set(_ value: String?, for account: String) throws
    func get(_ account: String) -> String?
    func delete(_ account: String)
}

/// Low-level Keychain wrapper used by `ModuleSecretStore`.
///
/// - service: `"com.wenjiexu.GlyphBar.module"` (shared across all modules; per-module
///   isolation is achieved by prefixing the account with `module.<moduleID>.`).
/// - account: caller-supplied, e.g. `"module.deepseek.deepseek.apiKey"`.
@MainActor
final class KeychainBackend: SecretStoreBackend {
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

/// Per-module secret store backed by Keychain. UserDefaults is intentionally
/// not part of this path; secrets have one production backend.
@MainActor
final class ModuleSecretStore: Capability {
    static let declaredKey: CapabilityKey = .secretStore

    private let moduleID: String
    private let backend: any SecretStoreBackend

    init(
        moduleID: String,
        backend: (any SecretStoreBackend)? = nil
    ) {
        self.moduleID = moduleID
        self.backend = backend ?? KeychainBackend()
    }

    func setSecret(_ value: String?, for rawKey: String) {
        try? backend.set(value, for: account(for: rawKey))
    }

    func secret(for rawKey: String) -> String? {
        backend.get(account(for: rawKey))
    }

    func deleteSecret(for rawKey: String) {
        backend.delete(account(for: rawKey))
    }

    private func account(for rawKey: String) -> String {
        "module.\(moduleID).\(rawKey)"
    }
}

@MainActor
final class InMemorySecretStoreBackend: SecretStoreBackend {
    private var values: [String: String] = [:]

    func set(_ value: String?, for account: String) throws {
        values[account] = value
    }

    func get(_ account: String) -> String? {
        values[account]
    }

    func delete(_ account: String) {
        values.removeValue(forKey: account)
    }
}
