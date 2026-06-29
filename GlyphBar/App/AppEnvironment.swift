import AppKit
import Foundation
import Observation
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
@Observable
final class SettingsNavigationState {
    var selectedSection: SettingsSection = .general
    var selectedModuleID: ModuleID?

    func open(section: SettingsSection, moduleID: ModuleID? = nil) {
        selectedSection = section
        selectedModuleID = moduleID
    }
}

@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    let logger: GlyphLogger
    let cacheStore: CacheStore
    let secureStore: SecureStore
    let permissionCenter: PermissionCenter
    let settingsStore: AppSettingsStore
    let widgetBridge: WidgetDataBridge
    let registry: ModuleRegistry
    let runtime: ModuleRuntime
    let envMonitor: SystemEnvironmentMonitor
    let settingsNavigation: SettingsNavigationState
    let quickPanelCoordinator: QuickPanelCoordinator
    let appMenuCoordinator: AppMenuCoordinator
    let statusItemController: StatusItemController
    let logsWindowCoordinator: LogsWindowCoordinator
    let router: DeepLinkRouter

    /// Bound by `AppDelegate` to the hosted scene's `openSettings` action.
    var openSettingsAction: (() -> Void)?

    private init() {
        let logger = GlyphLogger()
        let logsWindowCoordinator = LogsWindowCoordinator(logger: logger)
        let cacheStore = CacheStore()
        let secureStore = SecureStore()
        let permissionCenter = PermissionCenter()
        let settingsStore = AppSettingsStore()
        let widgetBridge = WidgetDataBridge()
        let settingsNavigation = SettingsNavigationState()

        // Build modules using CapabilityFactory — no per-module hardcoded
        // capability construction. The factory grants capabilities based on
        // each module's manifest permissions.
        let capabilityFactory = CapabilityFactory(logger: logger)

        let registry = ModuleRegistry()
        registry.register {
            let caps = capabilityFactory.makeCapabilities(
                for: "deepseek",
                manifest: DeepSeekModule.staticManifest,
                bridge: KernelBridge { _ in }
            )
            return DeepSeekModule(
                secretStore: caps.secretStore,
                settings: caps.settings,
                cache: caps.cache,
                network: caps.network,
                fileImport: caps.fileImport
            )
        }
        registry.register {
            let caps = capabilityFactory.makeCapabilities(
                for: "clock",
                manifest: ClockModule.staticManifest,
                bridge: KernelBridge { _ in }
            )
            return ClockModule(settings: caps.settings)
        }
        registry.register {
            let caps = capabilityFactory.makeCapabilities(
                for: "systemPulse",
                manifest: SystemPulseModule.staticManifest,
                bridge: KernelBridge { _ in }
            )
            return SystemPulseModule(systemMetrics: caps.systemMetrics)
        }
        registry.register {
            let caps = capabilityFactory.makeCapabilities(
                for: "notesQuick",
                manifest: NotesQuickModule.staticManifest,
                bridge: KernelBridge { _ in }
            )
            return NotesQuickModule(settings: caps.settings, cache: caps.cache)
        }
        registry.register {
            let caps = capabilityFactory.makeCapabilities(
                for: "counter",
                manifest: CounterModule.staticManifest,
                bridge: KernelBridge { _ in }
            )
            return CounterModule(settings: caps.settings, cache: caps.cache)
        }
        registry.register { NetworkMockModule() }

        let envMonitor = SystemEnvironmentMonitor()

        let runtime = ModuleRuntime(
            registry: registry,
            cacheStore: cacheStore,
            widgetBridge: widgetBridge,
            settingsStore: settingsStore,
            logger: logger
        )
        runtime.openSettingsAction = { [weak settingsNavigation] in
            settingsNavigation?.open(section: .general)
            AppEnvironment.shared.openSettingsAction?()
            NSApp.activate()
        }

        let appMenuCoordinator = AppMenuCoordinator(runtime: runtime)
        let quickPanelCoordinator = QuickPanelCoordinator(
            runtime: runtime,
            menuCoordinator: appMenuCoordinator,
            settingsStore: settingsStore
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
                NSApp.activate()
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
        self.widgetBridge = widgetBridge
        self.registry = registry
        self.runtime = runtime
        self.envMonitor = envMonitor
        self.settingsNavigation = settingsNavigation
        self.quickPanelCoordinator = quickPanelCoordinator
        self.logsWindowCoordinator = logsWindowCoordinator
        self.appMenuCoordinator = appMenuCoordinator
        self.statusItemController = statusItemController
        self.router = router

        // Module ordering is driven by manifest.priority, not hardcoded.
        // DeepSeek has priority: 100 in its manifest; others default to 0.
        // The runtime's orderedModuleIDs sorts by settingsStore.moduleOrder
        // first, then falls back to module ID. We seed moduleOrder with
        // priority-sorted IDs on first launch only.
        if settingsStore.moduleOrder.isEmpty {
            let prioritySorted = registry.makeRecords()
                .values
                .sorted { $0.module.manifest.priority > $1.module.manifest.priority }
                .map(\.id)
            settingsStore.moduleOrder = prioritySorted
        }
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
        // Use the SwiftUI openSettings action (bound from AppDelegate's
        // NSHostingSceneRepresentation) to open/focus the Settings window.
        openSettingsAction?()
        NSApp.activate()
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
            NSApp.activate()
            Task {
                await runtime.refresh(moduleID: moduleID)
            }
        } catch {
            runtime.userNotice = error.localizedDescription
            logger.error(error.localizedDescription)
            settingsNavigation.open(section: .modules)
            NSApp.activate()
        }
    }
}
