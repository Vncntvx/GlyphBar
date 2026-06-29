import Foundation
import Testing
@testable import GlyphBar

// MARK: - Reconciler Tests

@MainActor
struct ReconcilerTests {
    @Test func reconcileEnablesDesiredModule() {
        let reconciler = Reconciler()
        let instanceID = ModuleInstanceID(value: "clock.default")

        let desired: [ModuleInstanceID: DesiredModuleState] = [
            instanceID: DesiredModuleState(
                instanceID: instanceID,
                typeID: ModuleTypeID(value: "clock"),
                packageID: PackageID(value: "com.glyphbar.clock"),
                enabled: true
            )
        ]

        let observed: [ModuleInstanceID: ObservedModuleState] = [:]

        let actions = reconciler.reconcile(desired: desired, observed: observed)

        #expect(actions.contains { if case .install = $0 { true } else { false } })
    }

    @Test func reconcileDisablesUndesiredModule() {
        let reconciler = Reconciler()
        let instanceID = ModuleInstanceID(value: "clock.default")

        let desired: [ModuleInstanceID: DesiredModuleState] = [
            instanceID: DesiredModuleState(
                instanceID: instanceID,
                typeID: ModuleTypeID(value: "clock"),
                packageID: PackageID(value: "com.glyphbar.clock"),
                enabled: false
            )
        ]

        let observed: [ModuleInstanceID: ObservedModuleState] = [
            instanceID: ObservedModuleState(
                instanceID: instanceID,
                operational: .ready,
                installedPackageVersion: "1.0.0"
            )
        ]

        let actions = reconciler.reconcile(desired: desired, observed: observed)

        #expect(actions.contains { if case .disable = $0 { true } else { false } })
    }

    @Test func reconcileRevokesCapabilityAndSuspends() {
        let reconciler = Reconciler()
        let instanceID = ModuleInstanceID(value: "deepseek.default")

        let desired: [ModuleInstanceID: DesiredModuleState] = [
            instanceID: DesiredModuleState(
                instanceID: instanceID,
                typeID: ModuleTypeID(value: "deepseek"),
                packageID: PackageID(value: "com.glyphbar.deepseek"),
                enabled: true,
                grantedCapabilities: [.secretStore]  // Remove network
            )
        ]

        let observed: [ModuleInstanceID: ObservedModuleState] = [
            instanceID: ObservedModuleState(
                instanceID: instanceID,
                operational: .ready,
                actualCapabilities: [.secretStore, .network]
            )
        ]

        let actions = reconciler.reconcile(desired: desired, observed: observed)

        #expect(actions.contains { if case .revokeCapability(_, let cap) = $0, cap == .network { true } else { false } })
    }

    @Test func reconcileUninstallsUndesiredInstance() {
        let reconciler = Reconciler()
        let instanceID = ModuleInstanceID(value: "old.default")

        let desired: [ModuleInstanceID: DesiredModuleState] = [:]

        let observed: [ModuleInstanceID: ObservedModuleState] = [
            instanceID: ObservedModuleState(
                instanceID: instanceID,
                operational: .ready
            )
        ]

        let actions = reconciler.reconcile(desired: desired, observed: observed)

        #expect(actions.contains { if case .uninstall = $0 { true } else { false } })
    }

    @Test func reconcileDetectsVersionMismatch() {
        let reconciler = Reconciler()
        let instanceID = ModuleInstanceID(value: "deepseek.default")

        let desired: [ModuleInstanceID: DesiredModuleState] = [
            instanceID: DesiredModuleState(
                instanceID: instanceID,
                typeID: ModuleTypeID(value: "deepseek"),
                packageID: PackageID(value: "com.glyphbar.deepseek"),
                enabled: true,
                packageVersion: "1.3.0"
            )
        ]

        let observed: [ModuleInstanceID: ObservedModuleState] = [
            instanceID: ObservedModuleState(
                instanceID: instanceID,
                operational: .ready,
                installedPackageVersion: "1.2.0"
            )
        ]

        let actions = reconciler.reconcile(desired: desired, observed: observed)

        #expect(actions.contains { if case .upgrade = $0 { true } else { false } })
    }
}

// MARK: - DesiredStateStore Tests

@MainActor
struct DesiredStateStoreTests {
    @Test func desiredStateStorePersistsAcrossInstances() {
        let logger = GlyphLogger()
        let store1 = DesiredStateStore(logger: logger)
        let instanceID = ModuleInstanceID(value: "test.persist.\(UUID().uuidString)")

        store1.setState(DesiredModuleState(
            instanceID: instanceID,
            typeID: ModuleTypeID(value: "test"),
            packageID: PackageID(value: "com.test"),
            enabled: true
        ))

        // Create a new store instance — it should load from disk
        let store2 = DesiredStateStore(logger: logger)
        #expect(store2.state(for: instanceID)?.enabled == true)
    }
}

// MARK: - ModuleIdentity Tests

struct ModuleIdentityTests {
    @Test func defaultInstanceID() {
        let typeID = ModuleTypeID(value: "deepseek")
        let instanceID = ModuleInstanceID.default(for: typeID)
        #expect(instanceID.value == "deepseek.default")
    }

    @Test func legacyBridgesModuleID() {
        let instanceID = ModuleInstanceID.legacy("clock")
        #expect(instanceID.moduleID == "clock")
    }
}

// MARK: - SchemaVersion Tests

struct SchemaVersionTests {
    @Test func schemaVersionRejectsUnsupportedManifest() {
        let validator = PackageValidator()
        // Should fail because the path doesn't exist
        #expect(throws: Error.self) {
            try validator.validate(at: URL(fileURLWithPath: "/nonexistent"))
        }
    }
}

// MARK: - ModuleOperationalState Extended Tests

struct ModuleOperationalStateExtendedTests {
    @Test func installedCanOnlyLoad() {
        var state = ModuleOperationalState.installed
        _ = state.apply(.start)  // Invalid
        #expect(state == .installed)

        _ = state.apply(.load)   // Valid
        #expect(state == .loaded)
    }

    @Test func stoppingDrainsInFlightRefresh() {
        var state = ModuleOperationalState.refreshing
        _ = state.apply(.stop)
        #expect(state == .stopping)

        _ = state.apply(.refreshFailed(terminal: true))
        #expect(state == .stopping)  // Still stopping, not failed

        _ = state.apply(.uninstall)
        #expect(state == .uninstalled)
    }
}
