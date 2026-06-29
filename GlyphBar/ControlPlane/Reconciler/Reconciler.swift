import Foundation

/// Actions produced by the Reconciler to converge observed state toward desired state.
enum ReconcileAction: Sendable {
    case install(package: Package, instance: ModuleInstanceID)
    case upgrade(instance: ModuleInstanceID, to: Package)
    case enable(instance: ModuleInstanceID)
    case disable(instance: ModuleInstanceID)
    case grantCapability(instance: ModuleInstanceID, capability: CapabilityKey)
    case revokeCapability(instance: ModuleInstanceID, capability: CapabilityKey)
    case suspend(instance: ModuleInstanceID)
    case resume(instance: ModuleInstanceID)
    case uninstall(instance: ModuleInstanceID, preserveData: Bool)
    case migrateStorage(instance: ModuleInstanceID, from: Int, to: Int)
    case reauthenticate(instance: ModuleInstanceID)
    case clearAndRebuild(instance: ModuleInstanceID)
}

/// Compares desired vs observed state and produces reconcile actions.
@MainActor
final class Reconciler {
    private let logger: GlyphLogger

    init(logger: GlyphLogger = GlyphLogger()) {
        self.logger = logger
    }

    /// Reconcile all modules (batch diff).
    func reconcile(
        desired: [ModuleInstanceID: DesiredModuleState],
        observed: [ModuleInstanceID: ObservedModuleState]
    ) -> [ReconcileAction] {
        var actions: [ReconcileAction] = []

        // Desired instances not yet observed → install
        for (instanceID, desiredState) in desired {
            if observed[instanceID] == nil {
                // Not yet running — need to install/enable
                if desiredState.enabled {
                    let package = Package(
                        id: desiredState.packageID,
                        version: desiredState.packageVersion,
                        manifest: ModuleManifest(id: desiredState.typeID.value, displayName: desiredState.typeID.value, subtitle: "", systemImage: "circle", capabilities: [], permissions: [], defaultRefreshPolicy: desiredState.refreshPolicy, actions: [], widgets: []),
                        source: .builtIn,
                        installURL: nil
                    )
                    actions.append(.install(package: package, instance: instanceID))
                }
                continue
            }

            let observedState = observed[instanceID]!

            // Enable/disable
            if desiredState.enabled && observedState.operational == .suspended {
                actions.append(.resume(instance: instanceID))
            } else if !desiredState.enabled && observedState.operational != .suspended {
                actions.append(.disable(instance: instanceID))
            }

            // Capability grants/revocations
            let desiredCaps = desiredState.grantedCapabilities
            let observedCaps = observedState.actualCapabilities

            for cap in desiredCaps.subtracting(observedCaps) {
                actions.append(.grantCapability(instance: instanceID, capability: cap))
            }
            for cap in observedCaps.subtracting(desiredCaps) {
                actions.append(.revokeCapability(instance: instanceID, capability: cap))
            }

            // Version mismatch → upgrade
            if let installedVersion = observedState.installedPackageVersion,
               installedVersion != desiredState.packageVersion {
                let package = Package(
                    id: desiredState.packageID,
                    version: desiredState.packageVersion,
                    manifest: ModuleManifest(id: desiredState.typeID.value, displayName: desiredState.typeID.value, subtitle: "", systemImage: "circle", capabilities: [], permissions: [], defaultRefreshPolicy: desiredState.refreshPolicy, actions: [], widgets: []),
                    source: .builtIn,
                    installURL: nil
                )
                actions.append(.upgrade(instance: instanceID, to: package))
            }
        }

        // Observed instances no longer desired → uninstall
        for instanceID in observed.keys where desired[instanceID] == nil {
            actions.append(.uninstall(instance: instanceID, preserveData: false))
        }

        return actions
    }

    /// Apply reconcile actions against the runtime.
    func apply(_ actions: [ReconcileAction], supervisor: ModuleSupervisor, scheduler: RefreshScheduler) async {
        for action in actions {
            switch action {
            case .install(let package, let instanceID):
                logger.runtime("Reconciler: install \(package.id.value) as \(instanceID.value)")

            case .upgrade(let instanceID, let package):
                logger.runtime("Reconciler: upgrade \(instanceID.value) to \(package.version)")

            case .enable(let instanceID):
                logger.runtime("Reconciler: enable \(instanceID.value)")

            case .disable(let instanceID):
                logger.runtime("Reconciler: disable \(instanceID.value)")
                supervisor.cancelInFlight(for: instanceID.moduleID)

            case .grantCapability(let instanceID, let capability):
                logger.runtime("Reconciler: grant \(capability.rawValue) to \(instanceID.value)")

            case .revokeCapability(let instanceID, let capability):
                logger.runtime("Reconciler: revoke \(capability.rawValue) from \(instanceID.value)")
                supervisor.cancelInFlight(for: instanceID.moduleID)

            case .suspend(let instanceID):
                logger.runtime("Reconciler: suspend \(instanceID.value)")
                supervisor.cancelInFlight(for: instanceID.moduleID)

            case .resume(let instanceID):
                logger.runtime("Reconciler: resume \(instanceID.value)")

            case .uninstall(let instanceID, let preserveData):
                logger.runtime("Reconciler: uninstall \(instanceID.value) (preserveData: \(preserveData))")
                supervisor.unregister(moduleID: instanceID.moduleID)
                scheduler.unregister(id: instanceID.moduleID)

            case .migrateStorage(let instanceID, let from, let to):
                logger.runtime("Reconciler: migrate storage for \(instanceID.value) from v\(from) to v\(to)")

            case .reauthenticate(let instanceID):
                logger.runtime("Reconciler: reauthenticate \(instanceID.value)")

            case .clearAndRebuild(let instanceID):
                logger.runtime("Reconciler: clear and rebuild \(instanceID.value)")
            }
        }
    }
}
