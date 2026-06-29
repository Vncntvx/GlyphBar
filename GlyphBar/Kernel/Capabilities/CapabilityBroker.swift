import Foundation

/// Dynamic capability broker that manages capability grants for module instances.
/// The Reconciler uses this to converge observed capabilities toward desired
/// capabilities, and the Supervisor checks it before executing effects.
@MainActor
final class CapabilityBroker {
    private var grants: [ModuleInstanceID: Set<CapabilityKey>] = [:]
    private let logger: GlyphLogger

    /// Called when a grant/revoke triggers reconciliation.
    var onGrantChange: ((ModuleInstanceID, CapabilityKey, Bool) -> Void)?

    init(logger: GlyphLogger = GlyphLogger()) {
        self.logger = logger
    }

    /// Grant a capability to a module instance. Triggers reconciliation.
    func grant(_ key: CapabilityKey, to instance: ModuleInstanceID) {
        grants[instance, default: []].insert(key)
        logger.runtime("CapabilityBroker: grant \(key.rawValue) to \(instance.value)")
        onGrantChange?(instance, key, true)
    }

    /// Revoke a capability from a module instance. Triggers reconciliation.
    func revoke(_ key: CapabilityKey, from instance: ModuleInstanceID) {
        grants[instance, default: []].remove(key)
        logger.runtime("CapabilityBroker: revoke \(key.rawValue) from \(instance.value)")
        onGrantChange?(instance, key, false)
    }

    /// Current capability grants for a module instance.
    func currentGrants(for instance: ModuleInstanceID) -> Set<CapabilityKey> {
        grants[instance] ?? []
    }

    /// Set all grants for a module instance at once (e.g. from DesiredModuleState).
    func setGrants(_ keys: Set<CapabilityKey>, for instance: ModuleInstanceID) {
        grants[instance] = keys
    }
}
