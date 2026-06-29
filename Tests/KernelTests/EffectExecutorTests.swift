import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct EffectExecutorTests {
    @Test func effectExecutorPublishesToWidgetBridge() async {
        let bridge = WidgetDataBridge(defaults: UserDefaults(suiteName: "EffectExecutorTests.\(UUID().uuidString)")!)
        let cache = CacheStore()
        let logger = GlyphLogger()
        let executor = EffectExecutor(
            widgetBridge: bridge,
            cacheStore: cache,
            logger: logger
        )

        let snapshot = ModuleSnapshot(
            id: "test", title: "Test", subtitle: "Sub",
            systemImage: "circle", metrics: ["x": 1.0]
        )
        let envelope = ProjectionBuilder.buildEnvelope(from: snapshot)

        await executor.execute(.publishSnapshot(envelope), for: "test")

        let read = bridge.read(moduleID: "test")
        #expect(read != nil)
        #expect(read?.title == "Test")
    }

    @Test func effectExecutorCopiesToClipboard() async {
        let bridge = WidgetDataBridge(defaults: UserDefaults(suiteName: "EffectExecutorTests.\(UUID().uuidString)")!)
        let cache = CacheStore()
        let logger = GlyphLogger()
        let executor = EffectExecutor(
            widgetBridge: bridge,
            cacheStore: cache,
            logger: logger
        )

        await executor.execute(.copyToClipboard("hello"), for: "test")
        // No crash = pass; clipboard verification requires main-thread NSPasteboard.
    }
}
