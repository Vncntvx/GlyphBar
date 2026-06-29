import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct ModuleSecretStoreTests {
    @Test func moduleSecretStoreNamespaceIsolatesTwoModules() {
        let defaults = UserDefaults(suiteName: "SecretStoreTests.\(UUID().uuidString)")!
        let storeA = ModuleSecretStore(moduleID: "moduleA", legacyDefaults: defaults)
        let storeB = ModuleSecretStore(moduleID: "moduleB", legacyDefaults: defaults)

        storeA.setSecret("key-for-A", for: "api.key")
        storeB.setSecret("key-for-B", for: "api.key")

        #expect(storeA.secret(for: "api.key") == "key-for-A")
        #expect(storeB.secret(for: "api.key") == "key-for-B")
        #expect(storeA.secret(for: "api.key") != storeB.secret(for: "api.key"))
    }

    @Test func moduleSecretStoreReturnsNilForUnsetKey() {
        let store = ModuleSecretStore(moduleID: "emptyModule")
        #expect(store.secret(for: "nonexistent") == nil)
    }

    @Test func moduleSecretStoreDeleteRemovesSecret() {
        let store = ModuleSecretStore(moduleID: "deleteModule")
        store.setSecret("temp", for: "temp.key")
        #expect(store.secret(for: "temp.key") != nil)
        store.deleteSecret(for: "temp.key")
        #expect(store.secret(for: "temp.key") == nil)
    }
}
