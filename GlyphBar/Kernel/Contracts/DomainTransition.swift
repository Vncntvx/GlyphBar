import Foundation

/// Outcome of a module handling a command. The kernel's `EffectExecutor`
/// drains `effects`; `health` optionally updates the module's health state;
/// `refreshProjection` tells the kernel to re-call `buildProjection()`.
struct DomainTransition: Sendable {
    var effects: [Effect]
    var health: ModuleHealth?
    var refreshProjection: Bool

    static let empty = DomainTransition(effects: [], health: nil, refreshProjection: false)
}
