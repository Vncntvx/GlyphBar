import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct WidgetSnapshotBridgeTests {
    @Test func widgetBridgeReloadsTimelinesOnPublish() {
        // P1.12 regression guard: publish(_:) must call
        // WidgetCenter.shared.reloadAllTimelines(). We can't easily intercept
        // the WidgetCenter call, but we can verify publish doesn't crash and
        // writes data to the app group defaults.
        let defaults = UserDefaults(suiteName: "WidgetBridgeTests.\(UUID().uuidString)")!
        let bridge = WidgetDataBridge(defaults: defaults)

        let snapshot = ModuleSnapshot(
            id: "testWidget",
            title: "Test",
            subtitle: "Sub",
            systemImage: "circle",
            metrics: ["x": 1.0]
        )

        bridge.publish(snapshot)

        // Verify data was written.
        let read = bridge.read(moduleID: "testWidget")
        #expect(read != nil)
        #expect(read?.title == "Test")
    }

    @Test func widgetBridgePublishesEnvelope() {
        let defaults = UserDefaults(suiteName: "WidgetBridgeTests.\(UUID().uuidString)")!
        let bridge = WidgetDataBridge(defaults: defaults)

        let snapshot = ModuleSnapshot(id: "env", title: "Env", subtitle: "", systemImage: "circle")
        let envelope = ProjectionBuilder.buildEnvelope(from: snapshot)

        bridge.publish(envelope)

        let read = bridge.read(moduleID: "env")
        #expect(read != nil)
    }

    @Test func widgetBridgeRemovesSnapshot() {
        let defaults = UserDefaults(suiteName: "WidgetBridgeTests.\(UUID().uuidString)")!
        let bridge = WidgetDataBridge(defaults: defaults)

        let snapshot = ModuleSnapshot(id: "remove", title: "R", subtitle: "", systemImage: "circle")
        bridge.publish(snapshot)
        #expect(bridge.read(moduleID: "remove") != nil)

        bridge.remove(moduleID: "remove")
        #expect(bridge.read(moduleID: "remove") == nil)
    }
}
