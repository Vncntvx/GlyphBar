import Foundation

/// Strong-typed projection set. Each module produces one `ProjectionSet` per
/// refresh; the kernel wraps it in a `SnapshotEnvelope` for publication.
///
/// Uses optional struct fields rather than `[any Projection]` so the compiler
/// enforces the projection schema.
struct ProjectionSet: Sendable {
    var summary: SummaryProjection?
    var metrics: MetricsProjection?
    var list: ListProjection?
    var chart: ChartProjection?
    var statusCandidates: [StatusCandidate]
    var widget: WidgetProjection?
    var panelModel: PanelModelProjection?

    init(
        summary: SummaryProjection? = nil,
        metrics: MetricsProjection? = nil,
        list: ListProjection? = nil,
        chart: ChartProjection? = nil,
        statusCandidates: [StatusCandidate] = [],
        widget: WidgetProjection? = nil,
        panelModel: PanelModelProjection? = nil
    ) {
        self.summary = summary
        self.metrics = metrics
        self.list = list
        self.chart = chart
        self.statusCandidates = statusCandidates
        self.widget = widget
        self.panelModel = panelModel
    }
}
