import AppKit
import Combine
import Foundation

@MainActor
final class ModuleRuntime: ObservableObject {
    @Published private(set) var modules: [ModuleID: any ModuleContract]
    @Published private(set) var moduleRecords: [ModuleID: ModuleRecord]
    @Published private(set) var snapshots: [ModuleID: ModuleSnapshot] = [:]
    @Published var selectedModuleID: ModuleID?
    @Published var userNotice: String?

    let settingsStore: AppSettingsStore
    private let registry: ModuleRegistry
    private let scheduler: RefreshScheduler
    private let logger: GlyphLogger
    private let cacheStore: CacheStore
    private let widgetBridge: WidgetDataBridge
    private let capabilityFactory: CapabilityFactory

    init(
        registry: ModuleRegistry,
        cacheStore: CacheStore,
        widgetBridge: WidgetDataBridge,
        settingsStore: AppSettingsStore,
        logger: GlyphLogger = GlyphLogger(),
        scheduler: RefreshScheduler = RefreshScheduler()
    ) {
        let records = registry.makeRecords()
        self.registry = registry
        self.moduleRecords = records
        self.modules = records.mapValues(\.module)
        self.cacheStore = cacheStore
        self.widgetBridge = widgetBridge
        self.settingsStore = settingsStore
        self.scheduler = scheduler
        self.logger = logger
        self.capabilityFactory = CapabilityFactory(logger: logger)

        let manifests = modules.values.map(\.manifest).sorted { $0.displayName < $1.displayName }
        settingsStore.registerDefaults(for: manifests)
        selectedModuleID = settingsStore.primaryModuleID ?? manifests.first?.id

        for id in modules.keys {
            if let cached = cacheStore.load(moduleID: id) {
                snapshots[id] = cached.markedStale(reason: "Loaded cached snapshot")
            }
        }
    }

    var orderedModuleIDs: [ModuleID] {
        let knownIDs = Set(modules.keys)
        let ordered = settingsStore.moduleOrder.filter { knownIDs.contains($0) }
        let missing = modules.keys.filter { !ordered.contains($0) }.sorted()
        return ordered + missing
    }

    var enabledModuleIDs: [ModuleID] {
        orderedModuleIDs.filter { settingsStore.isEnabled($0) }
    }

    var builtInModuleIDs: [ModuleID] {
        orderedModuleIDs.filter { moduleRecords[$0]?.sourceKind == .builtIn }
    }

    var thirdPartyModuleIDs: [ModuleID] {
        orderedModuleIDs.filter { moduleRecords[$0]?.sourceKind == .thirdParty }
    }

    func start() {
        Task {
            await refreshEnabledModules(respectingPolicy: true)
        }
    }

    func refreshEnabledModules(respectingPolicy: Bool = false) async {
        for id in enabledModuleIDs {
            if respectingPolicy {
                let lastRefresh = snapshots[id]?.timestamp
                let policy = settingsStore.refreshPolicies[id] ?? modules[id]?.manifest.defaultRefreshPolicy ?? .manual
                guard scheduler.shouldRefresh(moduleID: id, policy: policy, lastRefresh: lastRefresh) else {
                    continue
                }
            }

            await refresh(moduleID: id)
        }
    }

    func refresh(moduleID: ModuleID) async {
        guard let module = modules[moduleID] else {
            return
        }

        let bridge = KernelBridge { [weak self] effects in
            guard let self else { return }
            for effect in effects {
                Task { await self.executeEffect(effect, for: moduleID) }
            }
        }
        let capabilities = capabilityFactory.makeCapabilities(
            for: moduleID,
            manifest: module.manifest,
            bridge: bridge
        )
        let transition = await module.handle(
            command: .refresh(reason: .scheduled),
            capabilities: capabilities,
            bridge: bridge
        )

        // Drain effects from the transition.
        for effect in transition.effects {
            await executeEffect(effect, for: moduleID)
        }

        if transition.refreshProjection {
            scheduler.recordSuccess(moduleID: moduleID)
            logger.runtime("Refreshed \(moduleID)")
        }
    }

    func dispatch(action: ModuleAction, moduleID: ModuleID) async {
        guard let module = modules[moduleID] else {
            return
        }

        let bridge = KernelBridge { [weak self] effects in
            guard let self else { return }
            for effect in effects {
                Task { await self.executeEffect(effect, for: moduleID) }
            }
        }
        let capabilities = capabilityFactory.makeCapabilities(
            for: moduleID,
            manifest: module.manifest,
            bridge: bridge
        )
        let transition = await module.handle(
            command: .userAction(actionID: action.id, payload: nil),
            capabilities: capabilities,
            bridge: bridge
        )

        for effect in transition.effects {
            await executeEffect(effect, for: moduleID)
        }
    }

    func setSelectedModule(_ moduleID: ModuleID?) {
        selectedModuleID = moduleID
    }

    func publishSnapshot(_ snapshot: ModuleSnapshot) {
        snapshots[snapshot.id] = snapshot
        cacheStore.save(snapshot)
        widgetBridge.publish(snapshot)
    }

    func record(for moduleID: ModuleID) -> ModuleRecord? {
        moduleRecords[moduleID]
    }

    @discardableResult
    func importModule(from sourceURL: URL, replacing: Bool = false) throws -> ModuleID {
        let package = try registry.importExternalPackage(from: sourceURL, replacing: replacing)
        reloadModules(selecting: package.moduleManifest.id)
        settingsStore.setEnabled(true, moduleID: package.moduleManifest.id)
        return package.moduleManifest.id
    }

    func removeThirdPartyModule(moduleID: ModuleID, removeData: Bool = true) throws {
        guard moduleRecords[moduleID]?.sourceKind == .thirdParty else {
            throw ExternalModuleError.notThirdParty(moduleID)
        }

        settingsStore.setEnabled(false, moduleID: moduleID)
        try registry.removeExternalPackage(moduleID: moduleID)
        if removeData {
            cacheStore.clear(moduleID: moduleID)
            widgetBridge.remove(moduleID: moduleID)
        }
        settingsStore.removeModuleState(moduleID: moduleID)
        reloadModules(selecting: enabledModuleIDs.first)
    }

    func storageLocation(for moduleID: ModuleID) -> URL? {
        guard moduleRecords[moduleID]?.sourceKind == .thirdParty else {
            return nil
        }
        return registry.externalStorageLocation(moduleID: moduleID)
    }

    // MARK: - Effect Execution

    /// Executes a single Effect produced by a module. This is the unified
    /// side-effect exit point — all module effects flow through here.
    private func executeEffect(_ effect: Effect, for moduleID: ModuleID) async {
        switch effect {
        case .publishSnapshot(let envelope):
            // Extract a ModuleSnapshot from the envelope for legacy consumers
            // (ModuleRuntime.snapshots, cacheStore, widgetBridge).
            let snapshot = ProjectionBuilder.buildSnapshot(from: envelope)
            snapshots[moduleID] = snapshot
            cacheStore.save(snapshot)
            widgetBridge.publish(envelope)

        case .persistDomainState(let data):
            logger.runtime("persistDomainState for \(moduleID) (\(data.count) bytes)")

        case .copyToClipboard(let value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            userNotice = "Copied"

        case .openURL(let url):
            NSWorkspace.shared.open(url)

        case .showNotice(let message):
            userNotice = message
            logger.info("Notice for \(moduleID): \(message)")

        case .openModuleSettings:
            openSettingsAction?()

        case .requestRefresh(let reason):
            await refresh(moduleID: moduleID)

        case .requestFileImport:
            logger.runtime("requestFileImport for \(moduleID) (capability wiring pending)")

        case .scheduleLocal(let command, let delay):
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let module = self.modules[moduleID] else { return }
                let bridge = KernelBridge { [weak self] effects in
                    guard let self else { return }
                    for effect in effects {
                        Task { await self.executeEffect(effect, for: moduleID) }
                    }
                }
                let capabilities = self.capabilityFactory.makeCapabilities(
                    for: moduleID,
                    manifest: module.manifest,
                    bridge: bridge
                )
                let _ = await module.handle(
                    command: command, capabilities: capabilities, bridge: bridge
                )
            }

        case .networkRequest:
            logger.warning("networkRequest effect should use NetworkCapability instead (module \(moduleID))")
        }
    }

    /// Closure set by AppEnvironment to open the settings window.
    /// Replaces the old `context.platformActions.showSettingsWindow()`.
    var openSettingsAction: (() -> Void)?

    private func reloadModules(selecting preferredModuleID: ModuleID?) {
        let records = registry.makeRecords()
        moduleRecords = records
        modules = records.mapValues(\.module)

        let manifests = modules.values.map(\.manifest).sorted { $0.displayName < $1.displayName }
        settingsStore.registerDefaults(for: manifests)

        if let preferredModuleID, modules[preferredModuleID] != nil {
            selectedModuleID = preferredModuleID
        } else if let selectedModuleID, modules[selectedModuleID] != nil {
            self.selectedModuleID = selectedModuleID
        } else {
            selectedModuleID = enabledModuleIDs.first ?? orderedModuleIDs.first
        }
    }
}

// MARK: - KernelBridge

/// A lightweight `ModuleBridge` implementation that buffers effects and
/// forwards them to a handler closure. Used by `ModuleRuntime` to give
/// modules a bridge when dispatching commands.
@MainActor
final class KernelBridge: ModuleBridge {
    private let handler: ([Effect]) -> Void

    init(handler: @escaping ([Effect]) -> Void) {
        self.handler = handler
    }

    func submit(_ effects: [Effect]) {
        handler(effects)
    }

    func submit(_ effect: Effect) {
        submit([effect])
    }
}
