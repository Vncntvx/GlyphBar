import Foundation

/// Strong-typed projection set. Each module produces one `ProjectionSet` per
/// refresh; the kernel wraps it in a `SnapshotEnvelope` for publication.
///
/// P1 uses optional struct fields (not `[any Projection]`) so the compiler
/// enforces the schema. P3 may add a `custom: [String: AnySendable]` escape
/// hatch for third-party modules.
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
