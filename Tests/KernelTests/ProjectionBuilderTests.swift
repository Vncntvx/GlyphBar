import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct ProjectionBuilderTests {
    @Test func projectionBuilderConvertsDeepSeekDomainStateToMetricsProjection() {
        let snapshot = ModuleSnapshot(
            id: "deepseek",
            title: "¥12.34",
            subtitle: "Today ¥1.23",
            systemImage: "brain.head.profile",
            metrics: [
                "totalBalance": 12.34,
                "todayCost": 1.23,
                "monthlyCost": 45.67
            ]
        )

        let projection = ProjectionBuilder.build(from: snapshot)

        #expect(projection.summary?.title == "¥12.34")
        #expect(projection.summary?.systemImage == "brain.head.profile")
        #expect(projection.metrics != nil)
        #expect(projection.metrics?.metrics.count == 3)

        let metricNames = projection.metrics?.metrics.map(\.id).sorted()
        #expect(metricNames == ["monthlyCost", "todayCost", "totalBalance"])
    }

    @Test func projectionBuilderIncludesWidgetProjection() {
        let snapshot = ModuleSnapshot(
            id: "clock",
            title: "12:00",
            subtitle: "Today",
            systemImage: "clock",
            signals: [StatusSignal(title: "Info", systemImage: "info", severity: .info, priority: 10)]
        )

        let projection = ProjectionBuilder.build(from: snapshot)

        #expect(projection.widget != nil)
        #expect(projection.widget?.title == "12:00")
        #expect(projection.widget?.severity == .info)
    }

    @Test func projectionBuilderBuildEnvelopeCarriesId() {
        let snapshot = ModuleSnapshot(id: "counter", title: "5", subtitle: "", systemImage: "number")
        let envelope = ProjectionBuilder.buildEnvelope(from: snapshot)

        #expect(envelope.id == "counter")
        #expect(envelope.projections.summary?.title == "5")
    }
}
