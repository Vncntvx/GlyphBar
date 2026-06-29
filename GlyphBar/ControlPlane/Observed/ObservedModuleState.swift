import Foundation

/// The observed runtime state of a module instance, as seen by the kernel.
/// The Reconciler compares this against `DesiredModuleState` to decide what
/// actions to take.
struct ObservedModuleState: Sendable, Equatable {
    let instanceID: ModuleInstanceID
    var operational: ModuleOperationalState
    var installedPackageVersion: String?
    var actualCapabilities: Set<CapabilityKey>
    var lastError: String?
    var runtimeGeneration: GenerationToken

    init(
        instanceID: ModuleInstanceID,
        operational: ModuleOperationalState = .installed,
        installedPackageVersion: String? = nil,
        actualCapabilities: Set<CapabilityKey> = [],
        lastError: String? = nil,
        runtimeGeneration: GenerationToken = .initial
    ) {
        self.instanceID = instanceID
        self.operational = operational
        self.installedPackageVersion = installedPackageVersion
        self.actualCapabilities = actualCapabilities
        self.lastError = lastError
        self.runtimeGeneration = runtimeGeneration
    }
}
