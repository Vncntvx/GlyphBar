import Foundation

/// The microkernel. P1 only defines the type — P1.11 wires it into
/// `ModuleRuntime` as the dispatch facade.
///
/// P1.8 scope:
/// - `register(_:)` stores modules by manifest.id
/// - `dispatch(_:for:)` routes a command to the matching module and drains the
///   resulting `DomainTransition.effects` via `EffectExecutor`
/// - `dispatchToAll(_:)` fans out to every registered module
/// - `submit(_:)` satisfies `ModuleBridge` so modules can emit effects mid-command
@MainActor
final class Kernel: ModuleBridge {
    private let effectExecutor: EffectExecutor
    private let logger: GlyphLogger
    private var modules: [ModuleID: any ModuleContract] = [:]
    private var pendingEffects: [(moduleID: ModuleID, effect: Effect)] = []

    init(effectExecutor: EffectExecutor, logger: GlyphLogger) {
        self.effectExecutor = effectExecutor
        self.logger = logger
    }

    func register(_ module: any ModuleContract) {
        modules[module.manifest.id] = module
    }

    func dispatch(_ command: Command, for moduleID: ModuleID) async {
        guard let module = modules[moduleID] else {
            logger.warning("Kernel: no module registered for \(moduleID)")
            return
        }

        // P1.11 will pass real GrantedCapabilities and a real bridge. For now,
        // we construct an empty capability set with `self` as the bridge.
        let bridge = self
        let capabilities = GrantedCapabilities(bridge: bridge)

        let transition = await module.handle(
            command: command,
            capabilities: capabilities,
            bridge: bridge
        )

        for effect in transition.effects {
            await effectExecutor.execute(effect, for: moduleID)
        }

        // Drain any effects submitted via the bridge during handle.
        let pending = pendingEffects
        pendingEffects.removeAll()
        for entry in pending {
            await effectExecutor.execute(entry.effect, for: entry.moduleID)
        }
    }

    func dispatchToAll(_ command: Command) async {
        for moduleID in modules.keys {
            await dispatch(command, for: moduleID)
        }
    }

    // MARK: - ModuleBridge

    func submit(_ effects: [Effect]) {
        // Bridge submissions carry no moduleID context; attribute to the
        // currently-dispatching module. P1.11 will tighten this with a
        // per-call scope.
        for effect in effects {
            pendingEffects.append((moduleID: "unknown", effect: effect))
        }
    }

    func submit(_ effect: Effect) {
        submit([effect])
    }
}
