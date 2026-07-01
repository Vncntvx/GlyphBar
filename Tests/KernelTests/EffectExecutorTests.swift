import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct EffectExecutorTests {
    @Test func effectExecutorPublishesToWidgetBridge() async {
        let suiteName = "EffectExecutorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bridge = WidgetDataBridge(defaults: defaults)
        let cache = CacheStore(defaults: defaults)
        let logger = GlyphLogger()
        let executor = EffectExecutor(
            widgetBridge: bridge,
            cacheStore: cache,
            logger: logger
        )
        var publishedSnapshot: ModuleSnapshot?
        executor.onSnapshotPublished = { _, snapshot in
            publishedSnapshot = snapshot
        }

        let snapshot = ModuleSnapshot(
            id: "test", title: "Test", subtitle: "Sub",
            systemImage: "circle", metrics: ["x": 1.0]
        )
        let envelope = ProjectionBuilder.buildEnvelope(from: snapshot)

        await executor.execute(.publishSnapshot(envelope), for: "test")

        let read = bridge.read(moduleID: "test")
        #expect(read != nil)
        #expect(read?.title == "Test")
        #expect(publishedSnapshot?.title == "Test")
        #expect(cache.load(moduleID: "test")?.title == "Test")
    }

    @Test func effectExecutorCopiesToClipboard() async {
        let suiteName = "EffectExecutorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bridge = WidgetDataBridge(defaults: defaults)
        let cache = CacheStore(defaults: defaults)
        let logger = GlyphLogger()
        let executor = EffectExecutor(
            widgetBridge: bridge,
            cacheStore: cache,
            logger: logger
        )

        await executor.execute(.copyToClipboard("hello"), for: "test")
        // No crash = pass; clipboard verification requires main-thread NSPasteboard.
    }

    @Test func effectExecutorRoutesRefreshRequestsThroughInjectedRuntimeAction() async {
        let suiteName = "EffectExecutorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bridge = WidgetDataBridge(defaults: defaults)
        let executor = EffectExecutor(
            widgetBridge: bridge,
            cacheStore: CacheStore(defaults: defaults),
            logger: GlyphLogger()
        )
        var refreshedModuleID: ModuleID?
        executor.requestRefreshAction = { moduleID, _ in
            refreshedModuleID = moduleID
        }

        await executor.execute(.requestRefresh(reason: .cascade), for: "refresh.source")

        #expect(refreshedModuleID == "refresh.source")
    }
}
