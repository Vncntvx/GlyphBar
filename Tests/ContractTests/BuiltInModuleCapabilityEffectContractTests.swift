import Foundation
import Testing
@testable import GlyphBar

// MARK: - DomainTransition Contract

struct DomainTransitionContractTests {
    @Test func emptyTransitionHasNoEffects() {
        let transition = DomainTransition.empty
        #expect(transition.effects.isEmpty)
        #expect(transition.health == nil)
        #expect(transition.refreshProjection == false)
    }

    @Test func domainTransitionWithEffects() {
        let transition = DomainTransition(
            effects: [.copyToClipboard("test")],
            health: .healthy,
            refreshProjection: true
        )
        #expect(transition.effects.count == 1)
        #expect(transition.health == .healthy)
        #expect(transition.refreshProjection == true)
    }
}

// MARK: - ModuleHealth Contract

struct ModuleHealthContractTests {
    @Test func healthyIsNotUnhealthy() {
        #expect(ModuleHealth.healthy.isUnhealthy == false)
        #expect(ModuleHealth.healthy.isTerminal == false)
    }

    @Test func degradedIsUnhealthyButNotTerminal() {
        let health = ModuleHealth.degraded(reason: .networkError("timeout"))
        #expect(health.isUnhealthy == true)
        #expect(health.isTerminal == false)
    }

    @Test func unavailableIsTerminal() {
        let health = ModuleHealth.unavailable(reason: .networkError("no connection"))
        #expect(health.isUnhealthy == true)
        #expect(health.isTerminal == true)
    }

    @Test func misconfiguredIsTerminal() {
        let health = ModuleHealth.misconfigured(reason: .missingSecret("apiKey"))
        #expect(health.isUnhealthy == true)
        #expect(health.isTerminal == true)
    }

    @Test func suspendedIsTerminal() {
        #expect(ModuleHealth.suspended.isUnhealthy == true)
        #expect(ModuleHealth.suspended.isTerminal == true)
    }
}

// MARK: - CapabilityFactory Contract

@MainActor
struct CapabilityFactoryContractTests {
    @Test func factoryGrantsCapabilitiesPerManifest() {
        let factory = CapabilityFactory()
        let bridge = makeBridge()

        let manifest = ModuleManifest(
            id: "test",
            displayName: "Test",
            subtitle: "",
            systemImage: "circle",
            capabilities: [.statusItem, .panel, .settings, .cachedState],
            permissions: [.pasteboard, .systemMetrics],
            defaultRefreshPolicy: .manual,
            actions: [],
            widgets: []
        )

        let capabilities = factory.makeCapabilities(for: "test", manifest: manifest, bridge: bridge)

        #expect(capabilities.clipboard != nil, "pasteboard permission → clipboard capability")
        #expect(capabilities.systemMetrics != nil, "systemMetrics permission → systemMetrics capability")
        #expect(capabilities.settings != nil, "settings capability → settings namespace")
        #expect(capabilities.cache != nil, "cachedState capability → cache namespace")
        #expect(capabilities.logging != nil, "logging always granted")
        #expect(capabilities.bridge === bridge, "factory should preserve the injected bridge")
    }

    @Test func factoryDoesNotGrantUndeclaredCapabilities() {
        let factory = CapabilityFactory()
        let bridge = makeBridge()

        let manifest = ModuleManifest(
            id: "minimal",
            displayName: "Minimal",
            subtitle: "",
            systemImage: "circle",
            capabilities: [.statusItem],
            permissions: [],
            defaultRefreshPolicy: .manual,
            actions: [],
            widgets: []
        )

        let capabilities = factory.makeCapabilities(for: "minimal", manifest: manifest, bridge: bridge)

        #expect(capabilities.network == nil, "no network permission → no network capability")
        #expect(capabilities.secretStore == nil, "no appGroupStorage → no secretStore")
        #expect(capabilities.clipboard == nil, "no pasteboard → no clipboard")
    }

    @Test func factoryGrantsSecretStoreForAppGroupStorage() {
        let factory = CapabilityFactory()
        let bridge = makeBridge()

        let manifest = ModuleManifest(
            id: "deepseek",
            displayName: "DeepSeek",
            subtitle: "",
            systemImage: "circle",
            capabilities: [.statusItem, .cachedState],
            permissions: [.appGroupStorage, .openExternalURLs],
            defaultRefreshPolicy: .manual,
            actions: [],
            widgets: []
        )

        let capabilities = factory.makeCapabilities(for: "deepseek", manifest: manifest, bridge: bridge)
        #expect(capabilities.secretStore != nil, "appGroupStorage → secretStore for key migration")
        #expect(capabilities.network != nil, "openExternalURLs → network capability")
    }

    @Test func factoryAlwaysGrantsLoggingAndBridge() {
        let factory = CapabilityFactory()
        let bridge = makeBridge()

        let manifest = ModuleManifest(
            id: "bare",
            displayName: "Bare",
            subtitle: "",
            systemImage: "circle",
            capabilities: [],
            permissions: [],
            defaultRefreshPolicy: .manual,
            actions: [],
            widgets: []
        )

        let capabilities = factory.makeCapabilities(for: "bare", manifest: manifest, bridge: bridge)
        #expect(capabilities.logging != nil, "logging is always granted")
        #expect(capabilities.bridge === bridge, "factory should preserve the injected bridge")
    }
}

// MARK: - Effect Contract

struct EffectContractTests {
    @Test func allEffectCasesAreRepresentable() {
        let _: [Effect] = [
            .publishSnapshot(SnapshotEnvelope(id: "test", projections: ProjectionSet())),
            .persistDomainState(Data()),
            .copyToClipboard("text"),
            .openURL(URL(string: "https://example.com")!),
            .showNotice("notice"),
            .openModuleSettings,
            .requestFileImport(FileImportRequest(allowedTypes: ["csv"])),
            .requestRefresh(reason: .manual),
            .scheduleLocal(.refresh(reason: .scheduled), after: 5),
        ]
    }

    @Test func fileImportRequestCarriesIDAndTypes() {
        let request = FileImportRequest(
            allowedTypes: ["csv", "zip"],
            allowDirectories: true
        )
        #expect(request.allowedTypes == ["csv", "zip"])
        #expect(request.allowDirectories == true)
        #expect(request.requestID != UUID())
    }
}
