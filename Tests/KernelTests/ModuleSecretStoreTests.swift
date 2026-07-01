import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct ModuleSecretStoreTests {
    @Test func moduleSecretStoreNamespaceIsolatesTwoModules() {
        let backend = InMemorySecretStoreBackend()
        let storeA = ModuleSecretStore(
            moduleID: "moduleA",
            backend: backend
        )
        let storeB = ModuleSecretStore(
            moduleID: "moduleB",
            backend: backend
        )

        storeA.setSecret("key-for-A", for: "api.key")
        storeB.setSecret("key-for-B", for: "api.key")

        #expect(storeA.secret(for: "api.key") == "key-for-A")
        #expect(storeB.secret(for: "api.key") == "key-for-B")
        #expect(storeA.secret(for: "api.key") != storeB.secret(for: "api.key"))
    }

    @Test func moduleSecretStoreReturnsNilForUnsetKey() {
        let store = ModuleSecretStore(moduleID: "emptyModule", backend: InMemorySecretStoreBackend())
        #expect(store.secret(for: "nonexistent") == nil)
    }

    @Test func moduleSecretStoreDeleteRemovesSecret() {
        let store = ModuleSecretStore(moduleID: "deleteModule", backend: InMemorySecretStoreBackend())
        store.setSecret("temp", for: "temp.key")
        #expect(store.secret(for: "temp.key") != nil)
        store.deleteSecret(for: "temp.key")
        #expect(store.secret(for: "temp.key") == nil)
    }

    @Test func moduleSecretStoreDoesNotReadPlaintextUserDefaultsFallback() {
        let suiteName = "SecretStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("plaintext-key", forKey: "plaintext.deepseek.apiKey")
        let store = ModuleSecretStore(
            moduleID: "deepseek",
            backend: InMemorySecretStoreBackend()
        )

        #expect(store.secret(for: "deepseek.apiKey") == nil)
        #expect(defaults.string(forKey: "plaintext.deepseek.apiKey") == "plaintext-key")
    }

    @Test func deletingSecretDoesNotDependOnPlaintextUserDefaults() {
        let suiteName = "SecretStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("plaintext-cookie", forKey: "plaintext.deepseek.platformCookie")
        let store = ModuleSecretStore(
            moduleID: "deepseek",
            backend: InMemorySecretStoreBackend()
        )

        store.deleteSecret(for: "deepseek.platformCookie")

        #expect(store.secret(for: "deepseek.platformCookie") == nil)
        #expect(defaults.string(forKey: "plaintext.deepseek.platformCookie") == "plaintext-cookie")
    }
}
