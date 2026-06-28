import Foundation
import Testing
@testable import GlyphBar

struct WidgetDataBridgeTests {
    @Test func widgetSnapshotRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "WidgetDataBridgeTests.\(UUID().uuidString)"))
        let bridge = WidgetDataBridge(defaults: defaults)
        let snapshot = WidgetModuleSnapshot(
            id: "clock",
            title: "10:00",
            subtitle: "Today",
            symbol: "clock",
            severity: .normal,
            metrics: [WidgetMetric(id: "offset", title: "Offset", value: "UTC+8", symbol: "globe")],
            notes: [],
            timestamp: Date(),
            unavailableReason: nil
        )

        bridge.write(snapshot, for: "clock")
        let read = bridge.read(moduleID: "clock")
        #expect(read != nil)
        #expect(read?.id == snapshot.id)
        #expect(read?.title == snapshot.title)
    }

    @Test func moduleSnapshotConversionCarriesUnavailableState() {
        let snapshot = ModuleSnapshot(
            id: "networkMock",
            title: "Offline",
            subtitle: "Timeout",
            systemImage: "wifi",
            freshness: .unavailable("Timed out"),
            signals: [StatusSignal(title: "Error", systemImage: "exclamationmark.octagon", severity: .critical)]
        )

        let widget = WidgetDataBridge.widgetSnapshot(from: snapshot)

        #expect(widget.severity == .critical)
        #expect(widget.unavailableReason == "Timed out")
    }
}
