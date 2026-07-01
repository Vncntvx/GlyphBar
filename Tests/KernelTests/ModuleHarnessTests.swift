import SwiftUI
import Testing
@testable import GlyphBar

@MainActor
final class HarnessReferenceModule: TypedModuleContribution {
    private var value = 0

    var manifest: ModuleManifest {
        ModuleManifest(
            id: "harness.reference",
            displayName: "Harness Reference",
            subtitle: "Reference module for headless tests",
            systemImage: "testtube.2",
            capabilities: [.statusItem, .panel, .widgets, .actions, .cachedState],
            permissions: [],
            defaultRefreshPolicy: .manual,
            actions: [
                ModuleAction(id: "increment", title: "Increment", systemImage: "plus"),
                ModuleAction(id: "scheduleIncrement", title: "Schedule Increment", systemImage: "timer")
            ],
            widgets: [
                ModuleWidgetDescriptor(
                    id: "harness.reference.widget",
                    title: "Harness Reference",
                    subtitle: "Reference widget output",
                    systemImage: "testtube.2",
                    supportedFamilies: ["small"]
                )
            ]
        )
    }

    func handle(
        command: Command,
        capabilities: GrantedCapabilities,
        bridge: ModuleBridge
    ) async -> DomainTransition {
        switch command {
        case .refresh:
            break
        case .userAction(let actionID, let payload) where actionID == "increment":
            value += Int(payload?.text ?? "1") ?? 1
        case .userAction(let actionID, let payload) where actionID == "scheduleIncrement":
            return DomainTransition(
                effects: [
                    .scheduleLocal(
                        .userAction(actionID: "increment", payload: payload),
                        after: 10
                    )
                ],
                health: .healthy,
                refreshProjection: false
            )
        default:
            return .empty
        }

        return DomainTransition(
            effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: snapshot()))],
            health: .healthy,
            refreshProjection: true
        )
    }

    func buildProjection() -> ProjectionSet {
        ProjectionBuilder.build(from: snapshot())
    }

    func statusCandidates() -> [StatusCandidate] {
        [
            StatusCandidate(
                id: "harness.reference.value",
                sourceModule: manifest.id,
                semanticRole: .primary,
                severity: .normal,
                priority: 10,
                text: "\(value)",
                icon: manifest.systemImage,
                createdAt: Date(),
                expiresAt: nil,
                interruptPolicy: .normal,
                trustLevel: .bundled
            )
        ]
    }

    func panelContent(context: PanelHostContext) -> some View {
        EmptyView()
    }

    private func snapshot() -> ModuleSnapshot {
        ModuleSnapshot(
            id: manifest.id,
            title: "\(value)",
            subtitle: "Value \(value)",
            systemImage: manifest.systemImage,
            metrics: ["value": Double(value)],
            notes: ["latest=\(value)"]
        )
    }
}

@MainActor
struct ModuleHarnessTests {
    @Test func harnessDispatchCapturesTransitionEffectsSnapshotAndWidgetOutput() async {
        let harness = ModuleHarness(module: HarnessReferenceModule())

        let transition = await harness.dispatch(.userAction(actionID: "increment", payload: .init(text: "2")))

        #expect(transition.refreshProjection == true)
        #expect(harness.transitions.count == 1)
        #expect(harness.emittedEffects.contains { effect in
            if case .publishSnapshot = effect { return true }
            return false
        })
        #expect(harness.latestSnapshot?.metrics["value"] == 2)
        #expect(harness.latestWidgetSnapshot?.title == "2")
        #expect(harness.latestWidgetSnapshot?.notes == ["latest=2"])
    }

    @Test func harnessUnloadStopsFurtherCommandExecution() async {
        let harness = ModuleHarness(module: HarnessReferenceModule())
        await harness.refresh()
        harness.unload()

        let transition = await harness.dispatch(.userAction(actionID: "increment", payload: nil))

        #expect(harness.isLoaded == false)
        #expect(transition.effects.isEmpty)
        #expect(harness.transitions.count == 1)
    }

    @Test func runtimeDispatchAndWaitPublishesSnapshotCacheAndWidgetDataHeadlessly() async {
        let suiteName = "RuntimeCommandFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = ModuleRegistry()
        registry.register { HarnessReferenceModule() }
        let widgetBridge = WidgetDataBridge(defaults: defaults)
        let runtime = ModuleRuntime(
            registry: registry,
            cacheStore: CacheStore(defaults: defaults),
            widgetBridge: widgetBridge,
            settingsStore: AppSettingsStore(defaults: defaults),
            logger: GlyphLogger()
        )

        let transition = await runtime.dispatchAndWait(
            command: .userAction(actionID: "increment", payload: .init(text: "3")),
            moduleID: "harness.reference"
        )

        #expect(transition?.refreshProjection == true)
        #expect(runtime.snapshots["harness.reference"]?.metrics["value"] == 3)
        #expect(CacheStore(defaults: defaults).load(moduleID: "harness.reference")?.title == "3")
        #expect(widgetBridge.read(moduleID: "harness.reference")?.title == "3")
    }

    @Test func runtimeScheduledLocalCommandFiresThroughVirtualClock() async {
        let suiteName = "RuntimeScheduleLocalTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = ModuleRegistry()
        registry.register { HarnessReferenceModule() }
        let clock = VirtualClock()
        let runtime = ModuleRuntime(
            registry: registry,
            cacheStore: CacheStore(defaults: defaults),
            widgetBridge: WidgetDataBridge(defaults: defaults),
            settingsStore: AppSettingsStore(defaults: defaults),
            logger: GlyphLogger(),
            localTaskClock: clock
        )
        runtime.settingsStore.setEnabled(true, moduleID: "harness.reference")

        await runtime.dispatchAndWait(
            command: .userAction(actionID: "scheduleIncrement", payload: .init(text: "4")),
            moduleID: "harness.reference"
        )

        #expect(runtime.snapshots["harness.reference"] == nil)

        clock.advance(by: 10)
        await yieldUntil {
            runtime.snapshots["harness.reference"]?.metrics["value"] == 4
        }

        #expect(runtime.snapshots["harness.reference"]?.metrics["value"] == 4)
    }

    @Test func runtimeCancelsScheduledLocalCommandWhenModuleIsDisabled() async {
        let suiteName = "RuntimeScheduleLocalCancelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = ModuleRegistry()
        registry.register { HarnessReferenceModule() }
        let clock = VirtualClock()
        let runtime = ModuleRuntime(
            registry: registry,
            cacheStore: CacheStore(defaults: defaults),
            widgetBridge: WidgetDataBridge(defaults: defaults),
            settingsStore: AppSettingsStore(defaults: defaults),
            logger: GlyphLogger(),
            localTaskClock: clock
        )
        runtime.settingsStore.setEnabled(true, moduleID: "harness.reference")

        await runtime.dispatchAndWait(
            command: .userAction(actionID: "scheduleIncrement", payload: .init(text: "4")),
            moduleID: "harness.reference"
        )
        runtime.setModuleEnabled(false, moduleID: "harness.reference")

        clock.advance(by: 10)
        await yieldUntil {
            runtime.snapshots["harness.reference"] != nil
        }

        #expect(runtime.snapshots["harness.reference"] == nil)
    }

    private func yieldUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<10 {
            if condition() { return }
            await Task.yield()
        }
    }
}
