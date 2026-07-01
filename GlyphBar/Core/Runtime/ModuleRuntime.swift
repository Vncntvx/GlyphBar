import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ModuleRuntime {
    private(set) var modules: [ModuleID: any ModuleContract]
    private(set) var moduleRecords: [ModuleID: ModuleRecord]
    private(set) var snapshots: [ModuleID: ModuleSnapshot] = [:]
    var selectedModuleID: ModuleID?
    var userNotice: String?

    let settingsStore: AppSettingsStore
    private let registry: ModuleRegistry
    private let scheduler: RefreshScheduler
    private let logger: GlyphLogger
    private let cacheStore: CacheStore
    private let widgetBridge: WidgetDataBridge
    private let capabilityFactory: CapabilityFactory
    private let supervisor: ModuleSupervisor
    private var scheduledLocalTasks: [ModuleID: [Task<Void, Never>]] = [:]

    init(
        registry: ModuleRegistry,
        cacheStore: CacheStore,
        widgetBridge: WidgetDataBridge,
        settingsStore: AppSettingsStore,
        logger: GlyphLogger = GlyphLogger(),
        permissionCenter: PermissionCenter? = nil,
        scheduler: RefreshScheduler? = nil
    ) {
        let records = registry.makeRecords()
        self.registry = registry
        self.moduleRecords = records
        self.modules = records.mapValues(\.module)
        self.cacheStore = cacheStore
        self.widgetBridge = widgetBridge
        self.settingsStore = settingsStore
        self.logger = logger
        self.capabilityFactory = CapabilityFactory(logger: logger, permissionCenter: permissionCenter)
        self.supervisor = ModuleSupervisor(capabilityFactory: self.capabilityFactory, logger: logger)

        // Use the new environment-aware scheduler by default
        self.scheduler = scheduler ?? RefreshScheduler()

        let manifests = modules.values.map(\.manifest).sorted { $0.displayName < $1.displayName }
        settingsStore.registerDefaults(for: manifests)
        selectedModuleID = settingsStore.primaryModuleID ?? manifests.first?.id

        for id in modules.keys {
            if let cached = cacheStore.load(moduleID: id) {
                snapshots[id] = cached.markedStale(reason: "Loaded cached snapshot")
            }
        }

        // Wire supervisor to execute effects
        supervisor.onEffects = { [weak self] moduleID, effects in
            guard let self else { return }
            for effect in effects {
                await self.executeEffect(effect, for: moduleID)
            }
        }

        // Register all modules with the supervisor
        for (id, module) in modules {
            supervisor.register(
                moduleID: id,
                module: module,
                sourceKind: records[id]?.sourceKind ?? .builtIn
            )
        }

        // Wire scheduler to dispatch refreshes through supervisor
        self.scheduler.onRefreshDue = { [weak self] moduleID in
            Task { @MainActor [weak self] in
                await self?.refresh(moduleID: moduleID)
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
        // Register enabled modules with the scheduler
        for id in enabledModuleIDs {
            if let module = modules[id] {
                let policy = settingsStore.refreshPolicies[id] ?? module.manifest.defaultRefreshPolicy
                scheduler.register(id: id, policy: policy)
            }
        }

        // Initial refresh for enabled modules
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
        guard modules[moduleID] != nil else { return }
        let transition = await supervisor.perform(.refresh(reason: .scheduled), for: moduleID)

        if transition?.refreshProjection == true {
            scheduler.recordSuccess(moduleID: moduleID)
            logger.runtime("Refreshed \(moduleID)")
        } else if transition?.health?.isUnhealthy == true {
            scheduler.recordFailure(moduleID: moduleID)
        }
    }

    @discardableResult
    func dispatch(action: ModuleAction, moduleID: ModuleID) async -> DomainTransition? {
        // Route through supervisor for serial processing + generation tracking
        return await dispatchAndWait(
            command: .userAction(actionID: action.id, payload: nil),
            moduleID: moduleID
        )
    }

    /// Dispatch a command with payload through the supervisor.
    /// Use this when the caller already has a `Command` with payload data
    /// (e.g. panel interactions that carry user input).
    func dispatch(command: Command, moduleID: ModuleID) {
        supervisor.dispatch(command, for: moduleID)
    }

    /// Dispatch a command and wait for the module transition. This is the
    /// headless API used by tests, deep links, and runtime operations that need
    /// deterministic completion.
    @discardableResult
    func dispatchAndWait(command: Command, moduleID: ModuleID) async -> DomainTransition? {
        await supervisor.perform(command, for: moduleID)
    }

    func setModuleEnabled(_ enabled: Bool, moduleID: ModuleID) {
        settingsStore.setEnabled(enabled, moduleID: moduleID)
        if enabled, let module = modules[moduleID] {
            let policy = settingsStore.refreshPolicies[moduleID] ?? module.manifest.defaultRefreshPolicy
            scheduler.register(id: moduleID, policy: policy)
            Task { await refresh(moduleID: moduleID) }
        } else {
            scheduler.unregister(id: moduleID)
            cancelScheduledLocalTasks(for: moduleID)
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
        setModuleEnabled(true, moduleID: package.moduleManifest.id)
        return package.moduleManifest.id
    }

    func removeThirdPartyModule(moduleID: ModuleID, removeData: Bool = true) throws {
        guard moduleRecords[moduleID]?.sourceKind == .thirdParty else {
            throw ExternalModuleError.notThirdParty(moduleID)
        }

        settingsStore.setEnabled(false, moduleID: moduleID)
        supervisor.unregister(moduleID: moduleID)
        scheduler.unregister(id: moduleID)
        cancelScheduledLocalTasks(for: moduleID)
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
            let task = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled, self.modules[moduleID] != nil else { return }
                await self.dispatchAndWait(command: command, moduleID: moduleID)
            }
            scheduledLocalTasks[moduleID, default: []].append(task)

        case .networkRequest:
            logger.warning("networkRequest effect should use NetworkCapability instead (module \(moduleID))")
        }
    }

    private func cancelScheduledLocalTasks(for moduleID: ModuleID) {
        scheduledLocalTasks[moduleID]?.forEach { $0.cancel() }
        scheduledLocalTasks[moduleID] = nil
    }

    /// Closure set by AppEnvironment to open the settings window.
    var openSettingsAction: (() -> Void)?

    private func reloadModules(selecting preferredModuleID: ModuleID?) {
        let records = registry.makeRecords()
        let removedIDs = Set(modules.keys).subtracting(records.keys)
        for id in removedIDs {
            supervisor.unregister(moduleID: id)
            scheduler.unregister(id: id)
            cancelScheduledLocalTasks(for: id)
        }

        moduleRecords = records
        modules = records.mapValues(\.module)

        let manifests = modules.values.map(\.manifest).sorted { $0.displayName < $1.displayName }
        settingsStore.registerDefaults(for: manifests)

        // Re-register all modules with the supervisor
        for (id, module) in modules {
            supervisor.register(
                moduleID: id,
                module: module,
                sourceKind: records[id]?.sourceKind ?? .builtIn
            )
        }

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
