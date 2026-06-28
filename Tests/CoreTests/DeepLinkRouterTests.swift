import AppKit
import Foundation
import Testing
@testable import GlyphBar

struct DeepLinkRouterTests {
    @Test func parsesModuleDeepLinks() throws {
        #expect(DeepLinkRouter.parse(try #require(URL(string: "glyphbar://module/clock"))) == .module("clock"))
        #expect(DeepLinkRouter.parse(try #require(URL(string: "glyphbar://module/clock/settings"))) == .moduleSettings("clock"))
        #expect(DeepLinkRouter.parse(try #require(URL(string: "glyphbar://module/counter/action/increment"))) == .moduleAction(moduleID: "counter", actionID: "increment"))
        #expect(DeepLinkRouter.parse(try #require(URL(string: "glyphbar://module/network-mock/action/retry"))) == .moduleAction(moduleID: "networkMock", actionID: "retry"))
    }

    @Test func parsesAppDeepLinks() throws {
        #expect(DeepLinkRouter.parse(try #require(URL(string: "glyphbar://app/panel"))) == .appPanel)
        #expect(DeepLinkRouter.parse(try #require(URL(string: "glyphbar://app/settings"))) == .appSettings)
        #expect(DeepLinkRouter.parse(try #require(URL(string: "glyphbar://app/modules"))) == .appModules)
        #expect(DeepLinkRouter.parse(try #require(URL(string: "glyphbar://app/logs"))) == .appLogs)
        #expect(DeepLinkRouter.parse(try #require(URL(string: "glyphbar://app/import-module"))) == .appImportModule)
    }

    @Test func rejectsInvalidLinks() throws {
        #expect(DeepLinkRouter.parse(try #require(URL(string: "https://module/clock"))) == nil)
        #expect(DeepLinkRouter.parse(try #require(URL(string: "glyphbar://module"))) == nil)
        #expect(DeepLinkRouter.parse(try #require(URL(string: "glyphbar://app/unknown"))) == nil)
    }

    @Test func dockVisibilityPersists() {
        let defaults = UserDefaults(suiteName: "DeepLinkRouterTests.\(UUID().uuidString)")!
        var store: AppSettingsStore? = AppSettingsStore(defaults: defaults)
        store?.showDockIcon = false
        store = nil

        #expect(AppSettingsStore(defaults: defaults).showDockIcon == false)
    }

    @MainActor
    @Test func moduleSettingsRouteOpensOnlySettings() {
        let runtime = makeRuntime()
        var panelOpenCount = 0
        var settingsSection: SettingsSection?
        var settingsModuleID: ModuleID?

        let router = DeepLinkRouter(
            runtime: runtime,
            logger: GlyphLogger(),
            openPanel: { panelOpenCount += 1 },
            openSettings: { section, moduleID in
                settingsSection = section
                settingsModuleID = moduleID
            },
            openLogs: {},
            importModule: {},
            showModule: { _ in panelOpenCount += 1 }
        )

        router.route(URL(string: "glyphbar://module/clock/settings")!)

        #expect(settingsSection == .modules)
        #expect(settingsModuleID == "clock")
        #expect(panelOpenCount == 0)
    }

    @MainActor
    private func makeRuntime() -> ModuleRuntime {
        let defaults = UserDefaults(suiteName: "DeepLinkRouterTests.\(UUID().uuidString)")!
        let logger = GlyphLogger()
        let cache = CacheStore(defaults: defaults)
        let context = ModuleContext(
            logger: logger,
            cacheStore: cache,
            secureStore: SecureStore(defaults: defaults),
            permissionCenter: PermissionCenter(defaults: defaults),
            settingsStore: AppSettingsStore(defaults: defaults),
            platformActions: PlatformActions(),
            widgetBridge: WidgetDataBridge(defaults: defaults)
        )
        let registry = ModuleRegistry()
        registry.register { ClockModule() }
        return ModuleRuntime(registry: registry, context: context, settingsStore: context.settingsStore)
    }
}
