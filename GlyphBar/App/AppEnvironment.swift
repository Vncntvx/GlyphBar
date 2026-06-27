import AppKit
import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    let logger: GlyphLogger
    let cacheStore: CacheStore
    let secureStore: SecureStore
    let permissionCenter: PermissionCenter
    let settingsStore: AppSettingsStore
    let platformActions: PlatformActions
    let widgetBridge: WidgetDataBridge
    let context: ModuleContext
    let registry: ModuleRegistry
    let runtime: ModuleRuntime
    let quickPanelCoordinator: QuickPanelCoordinator
    let appMenuCoordinator: AppMenuCoordinator
    let statusBarController: StatusBarController
    let mainWindowCoordinator: MainWindowCoordinator
    let router: DeepLinkRouter

    private init() {
        let logger = GlyphLogger()
        let cacheStore = CacheStore()
        let secureStore = SecureStore()
        let permissionCenter = PermissionCenter()
        let settingsStore = AppSettingsStore()
        let platformActions = PlatformActions()
        let widgetBridge = WidgetDataBridge()
        let context = ModuleContext(
            logger: logger,
            cacheStore: cacheStore,
            secureStore: secureStore,
            permissionCenter: permissionCenter,
            settingsStore: settingsStore,
            platformActions: platformActions,
            widgetBridge: widgetBridge
        )
        let registry = ModuleRegistry()
        registry.register { ClockModule() }
        registry.register { SystemPulseModule() }
        registry.register { NotesQuickModule() }
        registry.register { CounterModule() }
        registry.register { NetworkMockModule() }

        let runtime = ModuleRuntime(registry: registry, context: context, settingsStore: settingsStore)
        let quickPanelCoordinator = QuickPanelCoordinator(runtime: runtime)
        let mainWindowCoordinator = MainWindowCoordinator(platformActions: platformActions)
        let appMenuCoordinator = AppMenuCoordinator(runtime: runtime, platformActions: platformActions)
        let statusBarController = StatusBarController(
            runtime: runtime,
            settingsStore: settingsStore,
            panelCoordinator: quickPanelCoordinator,
            menuCoordinator: appMenuCoordinator
        )
        let router = DeepLinkRouter(
            runtime: runtime,
            logger: logger,
            openSettings: { platformActions.showSettingsWindow() },
            openModules: { platformActions.showSettingsWindow() },
            openLogs: { mainWindowCoordinator.openLogsWindow() },
            showModule: { moduleID in quickPanelCoordinator.show(moduleID: moduleID) }
        )

        self.logger = logger
        self.cacheStore = cacheStore
        self.secureStore = secureStore
        self.permissionCenter = permissionCenter
        self.settingsStore = settingsStore
        self.platformActions = platformActions
        self.widgetBridge = widgetBridge
        self.context = context
        self.registry = registry
        self.runtime = runtime
        self.quickPanelCoordinator = quickPanelCoordinator
        self.mainWindowCoordinator = mainWindowCoordinator
        self.appMenuCoordinator = appMenuCoordinator
        self.statusBarController = statusBarController
        self.router = router
    }

    func start() {
        statusBarController.start()
        runtime.start()
    }
}
