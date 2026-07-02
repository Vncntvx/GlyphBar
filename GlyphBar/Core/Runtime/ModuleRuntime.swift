import Foundation
import Observation

@MainActor
@Observable
final class ModuleRuntime {
    var modules: [ModuleID: any ModuleContract]
    var moduleRecords: [ModuleID: ModuleRecord]
    private(set) var snapshots: [ModuleID: ModuleSnapshot] = [:]
    var selectedModuleID: ModuleID?
    var userNotice: String?

    let settingsStore: AppSettingsStore
    let registry: ModuleRegistry
    let scheduler: RefreshScheduler
    let logger: GlyphLogger
    let cacheStore: CacheStore
    let widgetBridge: WidgetDataBridge
    let capabilityFactory: CapabilityFactory
    let supervisor: ModuleSupervisor
    let effectExecutor: EffectExecutor
    let localTaskClock: SchedulerClock
    var scheduledLocalHandles: [ModuleID: [ScheduledHandle]] = [:]

    init(
        registry: ModuleRegistry,
        cacheStore: CacheStore,
        widgetBridge: WidgetDataBridge,
        settingsStore: AppSettingsStore,
        logger: GlyphLogger = GlyphLogger(),
        permissionCenter: PermissionCenter? = nil,
        scheduler: RefreshScheduler? = nil,
        localTaskClock: SchedulerClock? = nil
    ) {
        let records = registry.makeRecords()
        self.registry = registry
        self.moduleRecords = records
        self.modules = records.mapValues(\.module)
        self.cacheStore = cacheStore
        self.widgetBridge = widgetBridge
        self.settingsStore = settingsStore
        self.logger = logger
        self.effectExecutor = EffectExecutor(
            widgetBridge: widgetBridge,
            cacheStore: cacheStore,
            logger: logger
        )
        self.localTaskClock = localTaskClock ?? SystemSchedulerClock()
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

        effectExecutor.onSnapshotPublished = { [weak self] moduleID, snapshot in
            self?.snapshots[moduleID] = snapshot
        }
        effectExecutor.onNotice = { [weak self] message in
            self?.userNotice = message
        }
        effectExecutor.requestRefreshAction = { [weak self] moduleID, _ in
            await self?.refresh(moduleID: moduleID)
        }
        effectExecutor.scheduleLocalAction = { [weak self] moduleID, command, delay in
            self?.scheduleLocal(command, for: moduleID, after: delay)
        }

        // Wire supervisor to the unified effect executor.
        supervisor.onEffects = { [weak self] moduleID, effects in
            guard let self else { return }
            for effect in effects {
                await self.effectExecutor.execute(effect, for: moduleID)
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

    /// Closure set by AppEnvironment to open the settings window.
    var openSettingsAction: (() -> Void)? {
        didSet {
            effectExecutor.openSettingsAction = openSettingsAction
        }
    }
}
