import XCTest
@testable import GlyphBar

final class WidgetDataBridgeTests: XCTestCase {
    func testWidgetSnapshotRoundTrip() {
        let defaults = UserDefaults(suiteName: "WidgetDataBridgeTests.\(UUID().uuidString)")!
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

        XCTAssertEqual(bridge.read(moduleID: "clock"), snapshot)
    }

    func testModuleSnapshotConversionCarriesUnavailableState() {
        let snapshot = ModuleSnapshot(
            id: "networkMock",
            title: "Offline",
            subtitle: "Timeout",
            systemImage: "wifi",
            freshness: .unavailable("Timed out"),
            signals: [StatusSignal(title: "Error", systemImage: "exclamationmark.octagon", severity: .critical)]
        )

        let widget = WidgetDataBridge.widgetSnapshot(from: snapshot)

        XCTAssertEqual(widget.severity, .critical)
        XCTAssertEqual(widget.unavailableReason, "Timed out")
    }
}
