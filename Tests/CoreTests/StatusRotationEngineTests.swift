import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct StatusRotationEngineTests {
    @Test func emptyRebuildProducesZeroItems() {
        let engine = StatusRotationEngine()
        engine.rebuild(modules: [:], snapshots: [:], enabledIDs: [], rotationModuleIDs: [], rotationItemIDs: [:])
        #expect(engine.count == 0)
        #expect(engine.tick() == nil)
    }

    @Test func rebuildIncludesOnlyEnabledAndRotationEnabledModules() {
        let engine = StatusRotationEngine()
        let snap = ModuleSnapshot(id: "clock", title: "12:00", subtitle: "", systemImage: "clock")
        let modules: [ModuleID: any StatusModule] = ["clock": ClockModule(), "counter": CounterModule()]
        let snapshots = ["clock": snap, "counter": snap]

        engine.rebuild(
            modules: modules,
            snapshots: snapshots,
            enabledIDs: ["clock", "counter"],
            rotationModuleIDs: ["clock"],  // only clock
            rotationItemIDs: [:]
        )

        #expect(engine.count == 1)
        let item = engine.tick()
        #expect(item?.title == "12:00")
        #expect(item?.systemImage == "clock")
    }

    @Test func tickAdvancesAndWrapsAround() {
        let engine = StatusRotationEngine()
        let clock = ModuleSnapshot(id: "clock", title: "12:00", subtitle: "", systemImage: "clock")
        let counter = ModuleSnapshot(id: "counter", title: "5", subtitle: "", systemImage: "number")

        engine.rebuild(
            modules: ["clock": ClockModule(), "counter": CounterModule()],
            snapshots: ["clock": clock, "counter": counter],
            enabledIDs: ["clock", "counter"],
            rotationModuleIDs: ["clock", "counter"],
            rotationItemIDs: ["clock": ["default"], "counter": ["default"]]
        )

        #expect(engine.count == 2)

        let first = engine.tick()
        let second = engine.tick()
        let third = engine.tick()  // wraps

        #expect(first?.title == "12:00")
        #expect(second?.title == "5")
        #expect(third?.title == "12:00")  // wrapped back
    }

    @Test func rebuildResetsOutOfBoundsIndex() {
        let engine = StatusRotationEngine()
        let snap = ModuleSnapshot(id: "clock", title: "12:00", subtitle: "", systemImage: "clock")

        engine.rebuild(
            modules: ["clock": ClockModule()],
            snapshots: ["clock": snap],
            enabledIDs: ["clock"],
            rotationModuleIDs: ["clock"],
            rotationItemIDs: ["clock": ["default"]]
        )
        #expect(engine.count == 1)

        _ = engine.tick()  // index now 0 (wrapped)
        _ = engine.tick()

        // rebuild with fewer items
        engine.rebuild(modules: [:], snapshots: [:], enabledIDs: [], rotationModuleIDs: [], rotationItemIDs: [:])
        #expect(engine.count == 0)
        #expect(engine.tick() == nil)
    }

    @Test func rebuildFallbackToFirstDescriptorWhenNoSelection() {
        let engine = StatusRotationEngine()
        // DeepSeekModule would return multiple descriptors, but with no selection
        // engine should use the first one
        let snap = ModuleSnapshot(id: "deepseek", title: "¥12.34", subtitle: "", systemImage: "brain.head.profile")
        let dsModule = DeepSeekModule()

        engine.rebuild(
            modules: ["deepseek": dsModule],
            snapshots: ["deepseek": snap],
            enabledIDs: ["deepseek"],
            rotationModuleIDs: ["deepseek"],
            rotationItemIDs: [:]  // no stored preferences
        )

        #expect(engine.count > 0)
        let item = engine.tick()
        #expect(item != nil)
    }

    @Test func tickReturnsNilWhenEmpty() {
        let engine = StatusRotationEngine()
        #expect(engine.tick() == nil)
    }

    @Test func moduleWithoutEnabledStatusIsSkipped() {
        let engine = StatusRotationEngine()
        let snap = ModuleSnapshot(id: "clock", title: "12:00", subtitle: "", systemImage: "clock")

        engine.rebuild(
            modules: ["clock": ClockModule()],
            snapshots: ["clock": snap],
            enabledIDs: [],  // nothing enabled
            rotationModuleIDs: ["clock"],
            rotationItemIDs: ["clock": ["default"]]
        )

        #expect(engine.count == 0)
    }
}
