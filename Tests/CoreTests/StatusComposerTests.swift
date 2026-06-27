import XCTest
@testable import GlyphBar

final class StatusComposerTests: XCTestCase {
    func testCriticalSignalOverridesPrimaryModule() {
        let composer = StatusComposer()
        let primary = ModuleSnapshot(id: "clock", title: "12:00", subtitle: "Today", systemImage: "clock")
        let failing = ModuleSnapshot(
            id: "networkMock",
            title: "Offline",
            subtitle: "Timeout",
            systemImage: "wifi",
            signals: [StatusSignal(title: "Network Down", message: "Timed out", systemImage: "exclamationmark.octagon", severity: .critical, priority: 10)]
        )

        let presentation = composer.compose(snapshots: ["clock": primary, "networkMock": failing], primaryModuleID: "clock")

        XCTAssertEqual(presentation.title, "Network Down")
        XCTAssertEqual(presentation.severity, .critical)
    }

    func testWarningAggregationBeatsPrimaryModule() {
        let composer = StatusComposer()
        let first = ModuleSnapshot(
            id: "a",
            title: "A",
            subtitle: "",
            systemImage: "a.circle",
            signals: [StatusSignal(title: "A Warning", systemImage: "exclamationmark.triangle", severity: .warning)]
        )
        let second = ModuleSnapshot(
            id: "b",
            title: "B",
            subtitle: "",
            systemImage: "b.circle",
            signals: [StatusSignal(title: "B Warning", systemImage: "exclamationmark.triangle", severity: .warning)]
        )

        let presentation = composer.compose(snapshots: ["a": first, "b": second], primaryModuleID: "a")

        XCTAssertEqual(presentation.title, "2 warnings")
        XCTAssertEqual(presentation.severity, .warning)
    }
}
