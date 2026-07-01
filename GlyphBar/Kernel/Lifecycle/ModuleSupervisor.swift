import Foundation

/// Supervises all module actors, dispatching commands and handling failures.
/// The supervisor ensures:
/// - Commands are dispatched to the correct module actor.
/// - Module-parallel: different modules can process commands concurrently.
/// - Module-serial: each module processes one command at a time.
/// - Failures are handled according to a supervision policy (retry/degrade/suspend/markFailed).
@MainActor
final class ModuleSupervisor {
    private var actors: [ModuleID: ModuleActor] = [:]
    private var sourceKinds: [ModuleID: ModuleSourceKind] = [:]
    private let capabilityFactory: CapabilityFactory
    private let logger: GlyphLogger

    /// Called when a module produces effects that need execution.
    var onEffects: ((ModuleID, [Effect]) async -> Void)?

    /// Called when a module's operational state changes.
    var onOperationalStateChange: ((ModuleID, ModuleOperationalState) -> Void)?

    init(capabilityFactory: CapabilityFactory, logger: GlyphLogger = GlyphLogger()) {
        self.capabilityFactory = capabilityFactory
        self.logger = logger
    }

    /// Register a module with the supervisor, creating an actor for it.
    func register(
        moduleID: ModuleID,
        module: any ModuleContract,
        sourceKind: ModuleSourceKind = .builtIn
    ) {
        let actor = ModuleActor(instanceID: moduleID)
        actor.onExecute = { [weak self] id, command, token in
            guard let self else { return .empty }
            return await self.executeCommand(moduleID: id, command: command, token: token, module: module)
        }
        actor.onStateChange = { [weak self] id, state in
            self?.onOperationalStateChange?(id, state)
        }
        actors[moduleID] = actor
        sourceKinds[moduleID] = sourceKind
    }

    /// Remove a module's actor from the supervisor.
    func unregister(moduleID: ModuleID) {
        actors[moduleID]?.cancelInFlight()
        actors.removeValue(forKey: moduleID)
        sourceKinds.removeValue(forKey: moduleID)
    }

    /// Dispatch a command to a specific module's actor.
    func dispatch(_ command: Command, for moduleID: ModuleID) {
        guard let actor = actors[moduleID] else {
            logger.warning("Supervisor: no actor for module \(moduleID)")
            return
        }
        actor.enqueue(command)
    }

    /// Dispatch a command and wait for the module's transition. This is the
    /// headless/testing path and is also used by runtime refreshes that need to
    /// record scheduler success/failure deterministically.
    func perform(_ command: Command, for moduleID: ModuleID) async -> DomainTransition? {
        guard let actor = actors[moduleID] else {
            logger.warning("Supervisor: no actor for module \(moduleID)")
            return nil
        }
        return await actor.perform(command)
    }

    /// Dispatch a command to all registered module actors (parallel).
    func dispatchToAll(_ command: Command) {
        for (id, actor) in actors {
            actor.enqueue(command)
            logger.runtime("Supervisor: dispatched \(command) to \(id)")
        }
    }

    /// Handle a module failure according to supervision policy.
    func handleFailure(_ moduleID: ModuleID, error: Error) -> SupervisionPolicy {
        logger.error("Supervisor: module \(moduleID) failed: \(error.localizedDescription)")

        // Simple policy: first failure → retry with backoff, repeated → degrade
        guard let actor = actors[moduleID] else { return .markFailed }
        switch actor.operationalState {
        case .failed:
            return .markFailed
        case .degraded:
            return .suspend
        default:
            return .retry(backoff: 5.0)
        }
    }

    /// Get the operational state of a module.
    func operationalState(for moduleID: ModuleID) -> ModuleOperationalState? {
        actors[moduleID]?.operationalState
    }

    /// Cancel in-flight work for a specific module.
    func cancelInFlight(for moduleID: ModuleID) {
        actors[moduleID]?.cancelInFlight()
    }

    // MARK: - Private

    private func executeCommand(
        moduleID: ModuleID,
        command: Command,
        token: GenerationToken,
        module: any ModuleContract
    ) async -> DomainTransition {
        let bridge = KernelBridge { [weak self] effects in
            guard let self else { return }
            Task { await self.onEffects?(moduleID, effects) }
        }
        let capabilities = capabilityFactory.makeCapabilities(
            for: moduleID,
            manifest: module.manifest,
            sourceKind: sourceKinds[moduleID] ?? .builtIn,
            bridge: bridge
        )

        let transition = await module.handle(
            command: command,
            capabilities: capabilities,
            bridge: bridge
        )
        if !transition.effects.isEmpty {
            await onEffects?(moduleID, transition.effects)
        }
        return transition
    }

    // MARK: - Supervision Policy

    enum SupervisionPolicy: Sendable, Equatable {
        case retry(backoff: TimeInterval)
        case degrade
        case suspend
        case markFailed
    }
}
