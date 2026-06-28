import Foundation
import Testing
@testable import GlyphBar

struct SettingsOverhaulTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "settings-overhaul-test-\(UUID().uuidString)")!
    }

    @Test func colorSchemePersists() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        store.colorScheme = "dark"
        #expect(defaults.string(forKey: "settings.colorScheme") == "dark")
        #expect(AppSettingsStore(defaults: defaults).colorScheme == "dark")
        #expect(AppSettingsStore(defaults: makeDefaults()).colorScheme == "system")
    }

    @Test func pinPanelPersists() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        store.pinPanel = true
        #expect(defaults.bool(forKey: "settings.pinPanel") == true)
        #expect(AppSettingsStore(defaults: defaults).pinPanel == true)
    }

    @Test func refreshPolicyWritesAndPersists() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        store.setRefreshPolicy(.interval(seconds: 60), for: "clock")
        #expect(store.refreshPolicies["clock"] == .interval(seconds: 60))
        #expect(AppSettingsStore(defaults: defaults).refreshPolicies["clock"] == .interval(seconds: 60))
    }

    @Test func loggerRingBufferAppendsAndCaps() {
        let logger = GlyphLogger()
        for index in 0..<600 { logger.info("message-\(index)") }
        let entries = logger.recentEntries()
        #expect(entries.count == 500)
        #expect(entries.last?.message == "message-599")
        #expect(entries.last?.category == "general")
        #expect(entries.last?.level == "info")
    }

    @Test func rotationEnabledPersists() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        store.statusRotationEnabled = true
        #expect(defaults.bool(forKey: "settings.statusRotationEnabled") == true)
        #expect(AppSettingsStore(defaults: defaults).statusRotationEnabled == true)
    }

    @Test func rotationIntervalPersists() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        #expect(store.statusRotationInterval == 5)
        store.statusRotationInterval = 10
        #expect(defaults.integer(forKey: "settings.statusRotationInterval") == 10)
        #expect(AppSettingsStore(defaults: defaults).statusRotationInterval == 10)
    }

    @Test func rotationModuleIDsPersists() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        store.rotationModuleIDs = ["clock", "counter"]
        let reloaded = AppSettingsStore(defaults: defaults)
        #expect(reloaded.rotationModuleIDs == ["clock", "counter"])
    }

    @Test func rotationItemIDsPersists() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        store.rotationItemIDs = ["clock": ["default", "balance"]]
        let reloaded = AppSettingsStore(defaults: defaults)
        #expect(reloaded.rotationItemIDs["clock"] == ["balance", "default"])
    }

    @Test func registerDefaultsPopulatesRotationDefaults() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        let manifests = [
            ModuleManifest(id: "clock", displayName: "Clock", subtitle: "", systemImage: "clock", version: "1.0", author: "", capabilities: [], permissions: [], defaultRefreshPolicy: .manual, actions: [], widgets: []),
            ModuleManifest(id: "counter", displayName: "Counter", subtitle: "", systemImage: "number", version: "1.0", author: "", capabilities: [], permissions: [], defaultRefreshPolicy: .manual, actions: [], widgets: []),
        ]
        store.registerDefaults(for: manifests)
        #expect(store.rotationModuleIDs.count == 2)
        #expect(store.rotationItemIDs["clock"] == ["default"])
        #expect(store.rotationItemIDs["counter"] == ["default"])
    }
}
