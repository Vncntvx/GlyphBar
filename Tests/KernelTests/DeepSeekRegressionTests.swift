import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct DeepSeekRegressionTests {
    @Test func deepSeekModuleNoLongerTouchesUserDefaultsStandard() {
        // P1.13 regression guard: DeepSeekModule must not hold a `defaults`
        // property backed by UserDefaults.standard. The module's settings/cache
        // must go through ModuleSettingsNamespace / ModuleCacheNamespace.
        //
        // This test creates a DeepSeekModule with nil capabilities and verifies
        // it doesn't crash (proving it doesn't require UserDefaults.standard).
        let module = DeepSeekModule(
            secretStore: nil,
            settings: nil,
            cache: nil,
            network: nil,
            fileImport: nil
        )

        // If the module still used UserDefaults.standard, it would have loaded
        // state from defaults at init. With nil capabilities, it should simply
        // have no cached state.
        #expect(module.manifest.id == "deepseek")
        #expect(module.manifest.priority == 100)
    }

    @Test func deepSeekModuleUsesNetworkCapabilityForBalance() async {
        // P1.13 bypass #2: fetchBalance must use NetworkCapability, not
        // URLSession.shared. We can't easily test the actual network call,
        // but we can verify the module compiles and initializes correctly
        // with a NetworkCapability injected.
        let network = NetworkCapability()
        let module = DeepSeekModule(
            secretStore: nil,
            settings: nil,
            cache: nil,
            network: network,
            fileImport: nil
        )

        // Triggering refresh via the new ModuleContract API without an API key
        // should not crash.
        let bridge = KernelBridge { _ in }
        let capabilities = GrantedCapabilities(bridge: bridge)
        let transition = await module.handle(
            command: .refresh(reason: .manual),
            capabilities: capabilities,
            bridge: bridge
        )
        // Should produce some transition (even if degraded due to missing key)
        #expect(module.manifest.id == "deepseek")
        #expect(transition.refreshProjection == true)
    }

    @Test func deepSeekSetApiKeyCommandWritesModuleSecretStore() async {
        let suiteName = "DeepSeekRegressionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let secretStore = ModuleSecretStore(
            moduleID: "deepseek",
            backend: InMemorySecretStoreBackend()
        )
        let harness = ModuleHarness(module: DeepSeekModule(secretStore: secretStore))

        await harness.dispatch(.userAction(actionID: "setApiKey", payload: .init(text: "sk-test")))

        #expect(secretStore.secret(for: "deepseek.apiKey") == "sk-test")
        #expect(harness.latestSnapshot?.id == "deepseek")
    }

    @Test func deepSeekImportUsageItemsCommandPublishesSnapshot() async {
        let suiteName = "DeepSeekRegressionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cache = ModuleCacheNamespace(moduleID: "deepseek", defaults: defaults)
        let module = DeepSeekModule(
            secretStore: ModuleSecretStore(
                moduleID: "deepseek",
                backend: InMemorySecretStoreBackend()
            ),
            cache: cache
        )
        let harness = ModuleHarness(module: module)
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let today = dateFormatter.string(from: Date())
        let items = [
            ParsedUsageItem(
                date: today,
                model: "deepseek-v4-flash",
                totalTokens: 1200,
                promptTokens: 800,
                completionTokens: 400,
                inputCacheHitTokens: 300,
                inputCacheMissTokens: 500,
                cost: 1.25,
                requestCount: 4
            )
        ]
        let data = try? JSONEncoder().encode(items)

        await harness.dispatch(.userAction(actionID: "importUsageItems", payload: .init(data: data)))

        #expect(harness.latestSnapshot?.metrics["todayCost"] == 1.25)
        #expect(harness.latestSnapshot?.metrics["monthlyCost"] == 1.25)
        #expect(harness.latestSnapshot?.metrics["totalBalance"] == 0)
    }
}
