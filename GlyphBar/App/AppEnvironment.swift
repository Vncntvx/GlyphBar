import AppKit
import Combine
import Foundation
import ServiceManagement

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case menuBar
    case modules
    case privacy
    case advanced
    case about

    var id: String { rawValue }
}

@MainActor
final class SettingsNavigationState: ObservableObject {
    @Published var selectedSection: SettingsSection = .general
    @Published var selectedModuleID: ModuleID?

    func open(section: SettingsSection, moduleID: ModuleID? = nil) {
        selectedSection = section
        selectedModuleID = moduleID
    }
}

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
    let settingsNavigation: SettingsNavigationState
    let quickPanelCoordinator: QuickPanelCoordinator
    let appMenuCoordinator: AppMenuCoordinator
    let statusItemController: StatusItemController
    let mainWindowCoordinator: MainWindowCoordinator
    let logsWindowCoordinator: LogsWindowCoordinator
    let router: DeepLinkRouter

    private init() {
        let logger = GlyphLogger()
        let logsWindowCoordinator = LogsWindowCoordinator(logger: logger)
        let cacheStore = CacheStore()
        let secureStore = SecureStore()
        let permissionCenter = PermissionCenter()
        let settingsStore = AppSettingsStore()
        let platformActions = PlatformActions()
        let widgetBridge = WidgetDataBridge()
        let settingsNavigation = SettingsNavigationState()
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
        let mainWindowCoordinator = MainWindowCoordinator(runtime: runtime, settingsStore: settingsStore)
        let appMenuCoordinator = AppMenuCoordinator(runtime: runtime, platformActions: platformActions)
        let quickPanelCoordinator = QuickPanelCoordinator(
            runtime: runtime,
            menuCoordinator: appMenuCoordinator,
            settingsStore: settingsStore,
            openFullWindow: {
                mainWindowCoordinator.openModuleWindow()
            }
        )
        let statusItemController = StatusItemController(
            runtime: runtime,
            settingsStore: settingsStore,
            panelCoordinator: quickPanelCoordinator,
            menuCoordinator: appMenuCoordinator,
            logger: logger
        )
        let router = DeepLinkRouter(
            runtime: runtime,
            logger: logger,
            openPanel: { quickPanelCoordinator.show(relativeTo: nil) },
            openSettings: { section, moduleID in
                settingsNavigation.open(section: section, moduleID: moduleID)
                platformActions.showSettingsWindow()
            },
            openLogs: { logsWindowCoordinator.open() },
            importModule: {
                AppEnvironment.shared.importModuleFromPanel()
            },
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
        self.settingsNavigation = settingsNavigation
        self.quickPanelCoordinator = quickPanelCoordinator
        self.mainWindowCoordinator = mainWindowCoordinator
        self.logsWindowCoordinator = logsWindowCoordinator
        self.appMenuCoordinator = appMenuCoordinator
        self.statusItemController = statusItemController
        self.router = router
    }

    func start() {
        statusItemController.start()
        runtime.start()
    }

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(settingsStore.showDockIcon ? .regular : .accessory)
        if settingsStore.showDockIcon {
            NSApp.activate(ignoringOtherApps: false)
        }
    }

    func applyLaunchAtLogin() {
        do {
            if settingsStore.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }

    func openSettings(section: SettingsSection = .general, moduleID: ModuleID? = nil) {
        settingsNavigation.open(section: section, moduleID: moduleID)
        platformActions.showSettingsWindow()
    }

    func openLogsWindow() {
        logsWindowCoordinator.open()
    }

    func importModuleFromPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import GlyphBar Module"
        panel.prompt = "Import"
        panel.message = "Choose a .glyphbarmodule package or folder containing glyphbar-module.json."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            let moduleID = try runtime.importModule(from: url)
            settingsNavigation.open(section: .modules, moduleID: moduleID)
            platformActions.showSettingsWindow()
            Task {
                await runtime.refresh(moduleID: moduleID)
            }
        } catch {
            runtime.userNotice = error.localizedDescription
            logger.error(error.localizedDescription)
            settingsNavigation.open(section: .modules)
            platformActions.showSettingsWindow()
        }
    }
}
