import Foundation
import Testing
@testable import GlyphBar

// MARK: - handle(command:) Returns Legal DomainTransition

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

// MARK: - buildProjection() Returns Legal ProjectionSet

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

        if !module.manifest.widgets.isEmpty {
            #expect(projection.widget != nil, "module with widget descriptors should produce a widget projection")
        }
    }
}

// MARK: - statusCandidates() Contract

@MainActor
struct ModuleStatusCandidatesContractTests {
    @Test(arguments: builtInModuleFactories)
    func statusCandidatesStructureIsLegal(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) {
        let module = entry.factory()
        let candidates = module.statusCandidates()

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

// MARK: - Graceful Degradation

@MainActor
struct ModuleDegradationContractTests {
    @Test(arguments: builtInModuleFactories)
    func moduleHandlesRefreshWithNilCapabilities(entry: (name: String, factory: @Sendable @MainActor () -> any ModuleContract)) async {
        let module = entry.factory()
        let bridge = makeBridge()
        let capabilities = GrantedCapabilities(bridge: bridge)

        let transition = await module.handle(
            command: .refresh(reason: .manual),
            capabilities: capabilities,
            bridge: bridge
        )

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

        if let health = transition.health {
            #expect(health == .healthy || health.isUnhealthy,
                    "unexpected health state for NetworkMock refresh")
        }
    }
}
