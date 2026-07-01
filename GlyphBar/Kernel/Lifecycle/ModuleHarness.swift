import Foundation

/// Headless module runner for unit tests and module development.
///
/// The harness intentionally reuses `ModuleSupervisor` and `CapabilityFactory`
/// so tests exercise the same command -> handle -> effect -> snapshot path as
/// the app runtime, without creating AppKit windows, status items, or settings UI.
@MainActor
final class ModuleHarness {
    let moduleID: ModuleID
    let module: any ModuleContract

    private let supervisor: ModuleSupervisor
    private let logger: GlyphLogger

    private(set) var emittedEffects: [Effect] = []
    private(set) var transitions: [DomainTransition] = []
    private(set) var latestEnvelope: SnapshotEnvelope?
    private(set) var latestSnapshot: ModuleSnapshot?
    private(set) var latestWidgetSnapshot: WidgetModuleSnapshot?
    private(set) var isLoaded = false

    init(
        module: any ModuleContract,
        sourceKind: ModuleSourceKind = .builtIn,
        permissionCenter: PermissionCenter? = nil,
        logger: GlyphLogger = GlyphLogger()
    ) {
        self.module = module
        self.moduleID = module.manifest.id
        self.logger = logger
        let factory = CapabilityFactory(logger: logger, permissionCenter: permissionCenter)
        self.supervisor = ModuleSupervisor(capabilityFactory: factory, logger: logger)
        self.supervisor.onEffects = { [weak self] moduleID, effects in
            await self?.record(effects: effects, moduleID: moduleID)
        }
        self.supervisor.register(moduleID: module.manifest.id, module: module, sourceKind: sourceKind)
        self.isLoaded = true
    }

    @discardableResult
    func dispatch(_ command: Command) async -> DomainTransition {
        guard isLoaded else { return .empty }
        let transition = await supervisor.perform(command, for: moduleID) ?? .empty
        transitions.append(transition)
        return transition
    }

    @discardableResult
    func refresh(reason: Command.RefreshReason = .manual) async -> DomainTransition {
        await dispatch(.refresh(reason: reason))
    }

    func stop() {
        supervisor.cancelInFlight(for: moduleID)
    }

    func unload() {
        supervisor.unregister(moduleID: moduleID)
        isLoaded = false
    }

    func resetCapturedOutput() {
        emittedEffects.removeAll()
        transitions.removeAll()
        latestEnvelope = nil
        latestSnapshot = nil
        latestWidgetSnapshot = nil
    }

    private func record(effects: [Effect], moduleID: ModuleID) {
        emittedEffects.append(contentsOf: effects)
        for effect in effects {
            guard case .publishSnapshot(let envelope) = effect else { continue }
            latestEnvelope = envelope
            let snapshot = ProjectionBuilder.buildSnapshot(from: envelope)
            latestSnapshot = snapshot
            latestWidgetSnapshot = WidgetDataBridge.widgetSnapshot(from: snapshot)
        }
    }
}
