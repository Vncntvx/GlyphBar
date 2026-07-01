import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct CapabilityEnforcementTests {
    @Test func thirdPartyCapabilitiesRequirePermissionCenterGrant() {
        let suiteName = "CapabilityEnforcementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let permissions = PermissionCenter(defaults: defaults)
        let factory = CapabilityFactory(logger: GlyphLogger(), permissionCenter: permissions)
        let manifest = manifestRequiringSensitiveCapabilities()
        let denied = factory.makeCapabilities(
            for: manifest.id,
            manifest: manifest,
            sourceKind: .thirdParty,
            bridge: KernelBridge { _ in }
        )

        #expect(denied.network == nil)
        #expect(denied.secretStore == nil)
        #expect(denied.cache == nil)
        #expect(denied.settings == nil)
        #expect(denied.clipboard == nil)
        #expect(denied.systemMetrics == nil)

        permissions.grant(.openExternalURLs)
        permissions.grant(.appGroupStorage)
        permissions.grant(.pasteboard)
        permissions.grant(.systemMetrics)

        let granted = factory.makeCapabilities(
            for: manifest.id,
            manifest: manifest,
            sourceKind: .thirdParty,
            bridge: KernelBridge { _ in }
        )

        #expect(granted.network != nil)
        #expect(granted.secretStore != nil)
        #expect(granted.cache != nil)
        #expect(granted.settings != nil)
        #expect(granted.clipboard != nil)
        #expect(granted.systemMetrics != nil)
    }

    @Test func builtInCapabilitiesAreGrantedFromManifestDeclarations() {
        let suiteName = "CapabilityEnforcementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let permissions = PermissionCenter(defaults: defaults)
        let factory = CapabilityFactory(logger: GlyphLogger(), permissionCenter: permissions)
        let manifest = manifestRequiringSensitiveCapabilities()

        let capabilities = factory.makeCapabilities(
            for: manifest.id,
            manifest: manifest,
            sourceKind: .builtIn,
            bridge: KernelBridge { _ in }
        )

        #expect(capabilities.network != nil)
        #expect(capabilities.secretStore != nil)
        #expect(capabilities.cache != nil)
        #expect(capabilities.settings != nil)
        #expect(capabilities.clipboard != nil)
        #expect(capabilities.systemMetrics != nil)
    }

    private func manifestRequiringSensitiveCapabilities() -> ModuleManifest {
        ModuleManifest(
            id: "thirdparty.capability-test",
            displayName: "Capability Test",
            subtitle: "Exercises permission enforcement",
            systemImage: "lock",
            capabilities: [.settings, .cachedState, .storage],
            permissions: [.openExternalURLs, .appGroupStorage, .pasteboard, .systemMetrics],
            defaultRefreshPolicy: .manual,
            actions: [],
            widgets: []
        )
    }
}
