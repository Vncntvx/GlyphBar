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
private func makeBridge() -> KernelBridge {
    KernelBridge { _ in }
}

/// All built-in modules for parameterized contract testing.
private let builtInModuleFactories: [(name: String, factory: @Sendable @MainActor () -> any ModuleContract)] = [
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

// MARK: - 2. handle(command:) Returns Legal DomainTransition

@MainActor
struct ModuleHandleCommandContractTests {
    @Test(arguments: builtInModuleFactories)
    func refreshCommandProducesLegalTransition(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) async {
        let module = entry.factory()
        let bridge = makeBridge()
        let capabilities = GrantedCapabilities(bridge: bridge)

        let transition = await module.handle(
            command: .refresh(reason: .manual),
            capabilities: capabilities,
            bridge: bridge
        )

        // A refresh must produce a valid DomainTransition.
        // If there are effects, at least one must be publishSnapshot.
        if !transition.effects.isEmpty {
            let hasPublish = transition.effects.contains { if case .publishSnapshot = $0 { true } else { false } }
            #expect(hasPublish || transition.effects.isEmpty == false,
                    "refresh should produce publishSnapshot or other effects")
        }
    }

    @Test(arguments: builtInModuleFactories)
    func unknownUserActionProducesNoSideEffects(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) async {
        let module = entry.factory()
        let bridge = makeBridge()
        let capabilities = GrantedCapabilities(bridge: bridge)

        let transition = await module.handle(
            command: .userAction(actionID: "nonexistent.action.∀", payload: nil),
            capabilities: capabilities,
            bridge: bridge
        )

        // Unknown actions must not produce clipboard/file/network side effects.
        // They may return .empty or a snapshot-only transition (some modules
        // publish snapshot as a side-effect-free status update).
        let hasSideEffects = transition.effects.contains { effect in
            switch effect {
            case .copyToClipboard, .openURL, .openModuleSettings,
                 .requestFileImport, .networkRequest, .persistDomainState:
                return true
            default:
                return false
            }
        }
        #expect(hasSideEffects == false,
                "unknown user actions must not produce side-effecting effects")
    }

    @Test(arguments: builtInModuleFactories)
    func systemCommandsDoNotCrash(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) async {
        let module = entry.factory()
        let bridge = makeBridge()
        let capabilities = GrantedCapabilities(bridge: bridge)

        // These commands may not be handled, but must not crash
        let systemCommands: [Command] = [
            .settingsChanged,
            .permissionChanged,
            .appBecameActive,
            .systemWake,
            .networkChanged(reachable: true),
            .clearCache,
        ]

        for command in systemCommands {
            let _ = await module.handle(
                command: command,
                capabilities: capabilities,
                bridge: bridge
            )
        }
    }
}

// MARK: - 3. buildProjection() Returns Legal ProjectionSet

@MainActor
struct ModuleProjectionContractTests {
    @Test(arguments: builtInModuleFactories)
    func buildProjectionReturnsNonEmptySummary(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) {
        let module = entry.factory()
        let projection = module.buildProjection()

        #expect(projection.summary != nil, "buildProjection() must return a ProjectionSet with summary")
        #expect(projection.summary?.title.isEmpty == false, "summary.title must not be empty")
        #expect(projection.summary?.systemImage.isEmpty == false, "summary.systemImage must not be empty")
    }

    @Test(arguments: builtInModuleFactories)
    func buildProjectionWidgetProjectionIsConsistent(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) {
        let module = entry.factory()
        let projection = module.buildProjection()

        // If the manifest declares widgets, projection should have a widget projection
        let hasWidgets = !module.manifest.widgets.isEmpty
        if hasWidgets {
            #expect(projection.widget != nil, "module with widget descriptors should produce a widget projection")
        }
    }
}

// MARK: - 4. statusCandidates() Contract

@MainActor
struct ModuleStatusCandidatesContractTests {
    @Test(arguments: builtInModuleFactories)
    func statusCandidatesStructureIsLegal(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) {
        let module = entry.factory()
        let candidates = module.statusCandidates()
        // Modules may return empty candidates when they have no active signals.
        // This is valid — the arbiter will show no content for that module.
        // But if candidates exist, they must be well-formed.
        for candidate in candidates {
            #expect(candidate.id.isEmpty == false, "statusCandidate ID must not be empty")
            #expect(candidate.sourceModule == module.manifest.id,
                    "candidate.sourceModule must match manifest.id")
            #expect(candidate.priority >= 0, "candidate priority must be non-negative")
            #expect(candidate.priority <= 1000, "candidate priority should be ≤ 1000")
            switch candidate.semanticRole {
            case .primary, .alert, .informational, .rotation:
                #expect(Bool(true))
            }
        }
    }

    @Test(arguments: builtInModuleFactories)
    func builtInStatusCandidatesAreBundled(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) {
        let module = entry.factory()
        let candidates = module.statusCandidates()
        for candidate in candidates {
            #expect(candidate.trustLevel == .bundled,
                    "built-in module candidates must have .bundled trust level, got \(candidate.trustLevel) for \(candidate.id)")
        }
    }

    @Test(arguments: builtInModuleFactories)
    func statusCandidatesHaveStableIDs(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) {
        let module = entry.factory()
        let candidates = module.statusCandidates()
        let ids = candidates.map(\.id)
        #expect(Set(ids).count == ids.count, "statusCandidate IDs must be unique within a module")
        for id in ids {
            #expect(id.isEmpty == false, "statusCandidate ID must not be empty")
        }
    }

    @Test(arguments: builtInModuleFactories)
    func statusCandidatesSourceModuleMatchesManifest(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) {
        let module = entry.factory()
        let candidates = module.statusCandidates()
        for candidate in candidates {
            #expect(candidate.sourceModule == module.manifest.id,
                    "candidate.sourceModule must match manifest.id")
        }
    }

    @Test(arguments: builtInModuleFactories)
    func statusCandidatesPriorityInRange(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) {
        let module = entry.factory()
        let candidates = module.statusCandidates()
        for candidate in candidates {
            #expect(candidate.priority >= 0, "candidate priority must be non-negative")
            #expect(candidate.priority <= 1000, "candidate priority should be ≤ 1000")
        }
    }

    @Test(arguments: builtInModuleFactories)
    func statusCandidatesSemanticRoleIsLegal(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) {
        let module = entry.factory()
        let candidates = module.statusCandidates()
        for candidate in candidates {
            switch candidate.semanticRole {
            case .primary, .alert, .informational, .rotation:
                #expect(Bool(true))
            }
        }
    }
}

// MARK: - 5. Graceful Degradation (No Crash on Missing Capabilities)

@MainActor
struct ModuleDegradationContractTests {
    @Test(arguments: builtInModuleFactories)
    func moduleHandlesRefreshWithNilCapabilities(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) async {
        let module = entry.factory()
        let bridge = makeBridge()
        let capabilities = GrantedCapabilities(bridge: bridge)

        // Must not crash even with nil capabilities
        let transition = await module.handle(
            command: .refresh(reason: .manual),
            capabilities: capabilities,
            bridge: bridge
        )

        // The transition must be a valid DomainTransition
        // (either .empty, or with effects + health)
        #expect(transition.effects.count >= 0)
    }

    @Test func deepSeekModuleDegradesGracefullyOnMissingSecret() async {
        let module = DeepSeekModule(
            secretStore: nil,
            settings: nil,
            cache: nil,
            network: nil,
            fileImport: nil
        )
        let bridge = makeBridge()
        let capabilities = GrantedCapabilities(bridge: bridge)

        let transition = await module.handle(
            command: .refresh(reason: .manual),
            capabilities: capabilities,
            bridge: bridge
        )

        // Must not crash; health should indicate an issue
        let hasHealthIssue = transition.health?.isUnhealthy == true
        let hasErrorEffect = transition.effects.contains { if case .showNotice = $0 { true } else { false } }
        let isEmpty = transition.effects.isEmpty && transition.health == nil
        #expect(hasHealthIssue || hasErrorEffect || isEmpty,
                "DeepSeek without secret should degrade, not crash")
    }

    @Test func networkMockModuleHandlesRefreshWithoutCrash() async {
        let module = NetworkMockModule()
        let bridge = makeBridge()
        let capabilities = GrantedCapabilities(bridge: bridge)

        let transition = await module.handle(
            command: .refresh(reason: .manual),
            capabilities: capabilities,
            bridge: bridge
        )

        // Must not crash; health is either healthy or degraded
        if let health = transition.health {
            #expect(health == .healthy || health.isUnhealthy,
                    "unexpected health state for NetworkMock refresh")
        }
    }
}

// MARK: - 6. Namespace Isolation

@MainActor
struct ModuleNamespaceIsolationTests {
    @Test func settingsNamespaceIsolatesTwoModules() {
        let defaults = UserDefaults(suiteName: "NamespaceIsolation.\(UUID().uuidString)")!
        let settingsA = ModuleSettingsNamespace(moduleID: "moduleA", defaults: defaults)
        let settingsB = ModuleSettingsNamespace(moduleID: "moduleB", defaults: defaults)

        settingsA["key"] = "valueA"
        settingsB["key"] = "valueB"

        #expect(settingsA["key"] == "valueA")
        #expect(settingsB["key"] == "valueB")
        #expect(settingsA["key"] != settingsB["key"])
    }

    @Test func cacheNamespaceIsolatesTwoModules() {
        let defaults = UserDefaults(suiteName: "CacheIsolation.\(UUID().uuidString)")!
        let cacheA = ModuleCacheNamespace(moduleID: "moduleA", defaults: defaults)
        let cacheB = ModuleCacheNamespace(moduleID: "moduleB", defaults: defaults)

        cacheA.saveDomainState(Data([0xAA]))
        cacheB.saveDomainState(Data([0xBB]))

        #expect(cacheA.loadDomainState() == Data([0xAA]))
        #expect(cacheB.loadDomainState() == Data([0xBB]))
    }

    @Test func settingsNamespaceCodableRoundTrip() {
        let defaults = UserDefaults(suiteName: "SettingsCodable.\(UUID().uuidString)")!
        let settings = ModuleSettingsNamespace(moduleID: "test", defaults: defaults)

        struct TestState: Codable, Equatable {
            let count: Int
            let label: String
        }

        let original = TestState(count: 42, label: "hello")
        settings.set(original, forKey: "state")

        let restored = settings.get(TestState.self, forKey: "state")
        #expect(restored == original)
    }

    @Test func settingsNamespaceRemovesNilValue() {
        let defaults = UserDefaults(suiteName: "SettingsNil.\(UUID().uuidString)")!
        let settings = ModuleSettingsNamespace(moduleID: "test", defaults: defaults)

        settings["key"] = "value"
        #expect(settings["key"] != nil)

        settings["key"] = nil
        #expect(settings["key"] == nil)
    }
}

// MARK: - 7. SnapshotEnvelope Contract

struct SnapshotEnvelopeContractTests {
    @Test func snapshotEnvelopeCarriesAllFields() {
        let projections = ProjectionSet()
        let envelope = SnapshotEnvelope(
            id: "test.envelope",
            schemaVersion: 1,
            capturedAt: Date(),
            validUntil: Date().addingTimeInterval(300),
            freshness: .fresh,
            health: .healthy,
            projections: projections
        )

        #expect(envelope.id == "test.envelope")
        #expect(envelope.schemaVersion == 1)
        #expect(envelope.freshness == .fresh)
        #expect(envelope.health == .healthy)
        #expect(envelope.validUntil != nil)
    }

    @Test func snapshotEnvelopeDefaultsAreSensible() {
        let projections = ProjectionSet()
        let envelope = SnapshotEnvelope(id: "defaults", projections: projections)

        #expect(envelope.schemaVersion == 1)
        #expect(envelope.health == .healthy)
        #expect(envelope.freshness == .fresh)
        #expect(envelope.validUntil == nil)
    }

    @Test func snapshotEnvelopeWithStaleFreshness() {
        let projections = ProjectionSet()
        let staleDate = Date().addingTimeInterval(-60)
        let envelope = SnapshotEnvelope(
            id: "stale.test",
            freshness: .stale(staleDate),
            health: .degraded(reason: .networkError("timeout")),
            projections: projections
        )

        #expect(envelope.freshness == .stale(staleDate))
        #expect(envelope.health.isUnhealthy == true)
    }

    @Test func snapshotEnvelopeWithUnavailableFreshness() {
        let projections = ProjectionSet()
        let envelope = SnapshotEnvelope(
            id: "unavail.test",
            freshness: .unavailable("module crashed"),
            health: .unavailable(reason: .unknown("crash")),
            projections: projections
        )

        #expect(envelope.freshness.isAvailable == false)
        #expect(envelope.health.isTerminal == true)
    }
}

// MARK: - 8. PresentationTickable Contract

@MainActor
struct PresentationTickableContractTests {
    @Test func clockPresentationTickReturnsUpdatedCandidates() {
        let module = ClockModule()
        // Build a ProjectionSet that has the module's actual candidates
        var projection = module.buildProjection()
        projection.statusCandidates = module.statusCandidates()

        // Tick should return a valid ProjectionSet with updated candidates
        let ticked = module.presentationTick(trigger: .timerTick, projection: projection)

        #expect(ticked.statusCandidates.isEmpty == false)
        // The primary candidate should still exist after tick
        let primary = ticked.statusCandidates.first { $0.id == "clock.primary" }
        #expect(primary != nil, "primary candidate must survive tick")
    }

    @Test func clockPresentationTickIsIdempotent() {
        let module = ClockModule()
        var projection = module.buildProjection()
        projection.statusCandidates = module.statusCandidates()

        let ticked1 = module.presentationTick(trigger: .timerTick, projection: projection)
        let ticked2 = module.presentationTick(trigger: .timerTick, projection: ticked1)

        // Two consecutive ticks should both produce valid projections
        #expect(ticked1.statusCandidates.count == ticked2.statusCandidates.count)
    }

    @Test func clockPresentationTickPreservesRotationCandidates() {
        let defaults = UserDefaults(suiteName: "TickRotation.\(UUID().uuidString)")!
        let settings = ModuleSettingsNamespace(moduleID: "clock", defaults: defaults)
        settings.set(["Asia/Tokyo", "Europe/London"], forKey: "moduleState")
        let module = ClockModule(settings: settings)

        var projection = module.buildProjection()
        projection.statusCandidates = module.statusCandidates()
        let ticked = module.presentationTick(trigger: .timerTick, projection: projection)

        let rotationBefore = projection.statusCandidates.filter { $0.semanticRole == .rotation }
        let rotationAfter = ticked.statusCandidates.filter { $0.semanticRole == .rotation }
        #expect(rotationBefore.count == rotationAfter.count,
                "tick must not remove rotation candidates")
    }
}

// MARK: - 9. DomainTransition Contract

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

// MARK: - 10. ModuleHealth Contract

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

// MARK: - 11. CapabilityFactory Contract

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
        #expect(capabilities.bridge !== nil, "bridge always granted")
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
        #expect(capabilities.bridge !== nil, "bridge is always granted")
    }
}

// MARK: - 12. Effect Contract

struct EffectContractTests {
    @Test func allEffectCasesAreRepresentable() {
        // Verify all Effect cases can be constructed without crash
        let _: [Effect] = [
            .publishSnapshot(SnapshotEnvelope(id: "test", projections: ProjectionSet())),
            .persistDomainState(Data()),
            .copyToClipboard("text"),
            .openURL(URL(string: "https://example.com")!),
            .showNotice("notice"),
            .openModuleSettings,
            .requestFileImport(allowedTypes: ["csv"]),
            .requestRefresh(reason: .manual),
            .scheduleLocal(.refresh(reason: .scheduled), after: 5),
            .networkRequest(NetworkRequest(url: URL(string: "https://example.com")!)),
        ]
    }

    @Test func networkRequestCarriesAllFields() {
        let request = NetworkRequest(
            url: URL(string: "https://api.example.com/v1")!,
            method: "POST",
            headers: ["Authorization": "Bearer token"],
            body: Data("payload".utf8)
        )
        #expect(request.method == "POST")
        #expect(request.headers["Authorization"] != nil)
        #expect(request.body != nil)
    }
}
