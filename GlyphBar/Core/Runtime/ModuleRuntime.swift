import Foundation

@MainActor
final class ModuleRuntime: ObservableObject {
    @Published private(set) var modules: [ModuleID: any StatusModule]
    @Published private(set) var snapshots: [ModuleID: ModuleSnapshot] = [:]
    @Published var selectedModuleID: ModuleID?
    @Published var userNotice: String?

    let context: ModuleContext
    let settingsStore: AppSettingsStore
    private let scheduler: RefreshScheduler
    private let logger: GlyphLogger

    init(
        registry: ModuleRegistry,
        context: ModuleContext,
        settingsStore: AppSettingsStore,
        scheduler: RefreshScheduler = RefreshScheduler()
    ) {
        self.modules = registry.makeModules()
        self.context = context
        self.settingsStore = settingsStore
        self.scheduler = scheduler
        self.logger = context.logger

        let manifests = modules.values.map(\.manifest).sorted { $0.displayName < $1.displayName }
        settingsStore.registerDefaults(for: manifests)
        selectedModuleID = settingsStore.primaryModuleID ?? manifests.first?.id

        for id in modules.keys {
            if let cached = context.cacheStore.load(moduleID: id) {
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

        do {
            let snapshot = try await module.refresh(context: context)
            snapshots[moduleID] = snapshot
            context.cacheStore.save(snapshot)
            context.widgetBridge.publish(snapshot)
            scheduler.recordSuccess(moduleID: moduleID)
            logger.runtime("Refreshed \(moduleID)")
        } catch {
            let fallback = context.cacheStore.load(moduleID: moduleID)?.markedStale(reason: error.localizedDescription)
            let snapshot = fallback ?? ModuleSnapshot(
                id: moduleID,
                title: module.manifest.displayName,
                subtitle: error.localizedDescription,
                systemImage: module.manifest.systemImage,
                freshness: .unavailable(error.localizedDescription),
                signals: [StatusSignal(
                    title: "Error",
                    message: error.localizedDescription,
                    systemImage: "exclamationmark.octagon",
                    severity: .critical,
                    priority: 100
                )]
            )
            snapshots[moduleID] = snapshot
            context.widgetBridge.publish(snapshot)
            let delay = scheduler.recordFailure(moduleID: moduleID)
            logger.warning("Refresh failed for \(moduleID); retry in \(delay)s: \(error.localizedDescription)")
        }
    }

    func dispatch(action: ModuleAction, moduleID: ModuleID) async {
        guard let module = modules[moduleID] else {
            return
        }

        do {
            let event = try await module.handle(action: action, context: context)
            await apply(event)
        } catch {
            userNotice = error.localizedDescription
            logger.error("Action \(action.id) failed for \(moduleID): \(error.localizedDescription)")
        }
    }

    func setSelectedModule(_ moduleID: ModuleID?) {
        selectedModuleID = moduleID
    }

    private func apply(_ event: ModuleEvent) async {
        switch event {
        case .none:
            break
        case .didUpdateSnapshot(let snapshot):
            snapshots[snapshot.id] = snapshot
            context.cacheStore.save(snapshot)
            context.widgetBridge.publish(snapshot)
        case .copyToPasteboard(let value):
            context.platformActions.copyToPasteboard(value)
            userNotice = "Copied"
        case .refreshRequested(let moduleID), .stateChanged(let moduleID):
            await refresh(moduleID: moduleID)
        case .userNotice(let message):
            userNotice = message
        case .openSettings:
            context.platformActions.showSettingsWindow()
        }
    }
}
