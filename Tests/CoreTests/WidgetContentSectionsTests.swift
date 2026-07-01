import Foundation
import Testing
@testable import GlyphBar

struct WidgetContentSectionsTests {
    @Test func widgetContentIncludesMetricsAndNotesWhenBothExist() {
        let snapshot = WidgetModuleSnapshot(
            id: "mixed",
            title: "Mixed",
            subtitle: "Metrics and notes",
            symbol: "chart.bar",
            severity: .info,
            metrics: [
                WidgetMetric(id: "a", title: "A", value: "1", symbol: "1.circle"),
                WidgetMetric(id: "b", title: "B", value: "2", symbol: "2.circle")
            ],
            notes: ["first", "second"],
            timestamp: Date(),
            unavailableReason: nil
        )

        let sections = WidgetContentSections(snapshot: snapshot, metricLimit: 2, noteLimit: 2)

        #expect(sections.metrics.map(\.id) == ["a", "b"])
        #expect(sections.notes == ["first", "second"])
        #expect(sections.unavailableReason == nil)
    }

    @Test func unavailableWidgetContentSuppressesMetricsAndNotes() {
        let snapshot = WidgetModuleSnapshot(
            id: "unavailable",
            title: "Unavailable",
            subtitle: "No data",
            symbol: "exclamationmark.triangle",
            severity: .warning,
            metrics: [
                WidgetMetric(id: "a", title: "A", value: "1", symbol: "1.circle")
            ],
            notes: ["hidden"],
            timestamp: Date(),
            unavailableReason: "No cached snapshot"
        )

        let sections = WidgetContentSections(snapshot: snapshot, metricLimit: 2, noteLimit: 2)

        #expect(sections.unavailableReason == "No cached snapshot")
        #expect(sections.metrics.isEmpty)
        #expect(sections.notes.isEmpty)
    }
}
