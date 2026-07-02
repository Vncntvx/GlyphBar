import Foundation
import Testing
@testable import GlyphBar

// MARK: - Module Contract Conformance Tests
//
// These test the PARADIGM constraints that every module must satisfy,
// not module-specific business logic. The paradigm requires:
//
// 1. ModuleContract: manifest, handle, buildProjection, statusCandidates
// 2. All side effects flow through DomainTransition.effects (no bypasses)
// 3. statusCandidates carry correct trust level for their source
// 4. buildProjection() returns a non-empty ProjectionSet
// 5. manifest has a legal id, version, and refresh policy
// 6. Modules degrade gracefully when capabilities are missing
// 7. Namespace isolation: settings/cache/secrets are per-module
// 8. SnapshotEnvelope is Codable
// 9. PresentationTickable: tick is pure (no side effects)
// 10. Third-party modules obey the same contract

// MARK: - Shared Helpers

@MainActor
func makeBridge() -> KernelBridge {
    KernelBridge { _ in }
}

/// All built-in modules for parameterized contract testing.
let builtInModuleFactories: [(name: String, factory: @Sendable @MainActor () -> any ModuleContract)] = [
    ("clock", { ClockModule() }),
    ("counter", { CounterModule() }),
    ("notesQuick", { NotesQuickModule() }),
    ("systemPulse", { SystemPulseModule() }),
    ("networkMock", { NetworkMockModule() }),
    ("deepseek", { DeepSeekModule() }),
]

// MARK: - 1. Manifest Legality

@MainActor
struct ModuleManifestLegalityTests {
    @Test(arguments: builtInModuleFactories)
    func manifestHasLegalID(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) {
        let module = entry.factory()
        let manifest = module.manifest
        #expect(manifest.id.isEmpty == false, "manifest.id must not be empty")
        #expect(manifest.id == entry.name, "manifest.id should match the registered name")
    }

    @Test(arguments: builtInModuleFactories)
    func manifestHasLegalVersion(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) {
        let module = entry.factory()
        let version = module.manifest.version
        #expect(version.isEmpty == false, "manifest.version must not be empty")
        // Version should look like semver (x.y.z)
        let parts = version.split(separator: ".")
        #expect(parts.count >= 2, "manifest.version should be semver-like (x.y.z)")
    }

    @Test(arguments: builtInModuleFactories)
    func manifestHasLegalRefreshPolicy(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) {
        let module = entry.factory()
        let policy = module.manifest.defaultRefreshPolicy
        // All policies are legal; just verify it's one of the known cases
        switch policy {
        case .manual, .onLaunch, .interval:
            #expect(Bool(true))
        }
    }

    @Test(arguments: builtInModuleFactories)
    func manifestPriorityInRange(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) {
        let module = entry.factory()
        #expect(module.manifest.priority >= 0, "manifest.priority must be non-negative")
        #expect(module.manifest.priority <= 1000, "manifest.priority should be 0...1000")
    }

    @Test(arguments: builtInModuleFactories)
    func manifestActionIDsAreStable(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) {
        let module = entry.factory()
        let actionIDs = module.manifest.actions.map(\.id)
        // Action IDs must be unique
        #expect(Set(actionIDs).count == actionIDs.count, "manifest.actions must have unique IDs")
        // Action IDs must be non-empty
        for id in actionIDs {
            #expect(id.isEmpty == false, "action ID must not be empty")
        }
    }
}
