import Foundation

/// Outcome of a module handling a command. `ModuleSupervisor` emits `effects`
/// to `EffectExecutor`; `health` optionally updates the module's health state;
/// `refreshProjection` asks the runtime to publish the module's latest projection.
struct DomainTransition: Sendable {
    var effects: [Effect]
    var health: ModuleHealth?
    var refreshProjection: Bool

    static let empty = DomainTransition(effects: [], health: nil, refreshProjection: false)
}
