import AppKit
import XCTest
@testable import GlyphBar

final class DeepLinkRouterTests: XCTestCase {
    func testParsesModuleDeepLinks() {
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://module/clock")!), .module("clock"))
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://module/clock/settings")!), .moduleSettings("clock"))
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://module/counter/action/increment")!), .moduleAction(moduleID: "counter", actionID: "increment"))
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://module/network-mock/action/retry")!), .moduleAction(moduleID: "networkMock", actionID: "retry"))
    }

    func testParsesAppDeepLinks() {
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://app/panel")!), .appPanel)
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://app/settings")!), .appSettings)
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://app/modules")!), .appModules)
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://app/logs")!), .appLogs)
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://app/import-module")!), .appImportModule)
    }

    func testRejectsInvalidLinks() {
        XCTAssertNil(DeepLinkRouter.parse(URL(string: "https://module/clock")!))
        XCTAssertNil(DeepLinkRouter.parse(URL(string: "glyphbar://module")!))
        XCTAssertNil(DeepLinkRouter.parse(URL(string: "glyphbar://app/unknown")!))
    }

    func testDockVisibilityPersists() {
        let defaults = UserDefaults(suiteName: "DeepLinkRouterTests.\(UUID().uuidString)")!
        var store: AppSettingsStore? = AppSettingsStore(defaults: defaults)
        store?.showDockIcon = false
        store = nil

        XCTAssertFalse(AppSettingsStore(defaults: defaults).showDockIcon)
    }

    @MainActor
    func testModuleSettingsRouteOpensOnlySettings() {
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

        XCTAssertEqual(settingsSection, .modules)
        XCTAssertEqual(settingsModuleID, "clock")
        XCTAssertEqual(panelOpenCount, 0)
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
