import Foundation

/// The projection consumed by WidgetKit timelines. `WidgetSnapshotBridge`
/// (P1.12) converts this to `WidgetModuleSnapshot` for the app group container.
struct WidgetProjection: Sendable {
    let title: String
    let subtitle: String
    let systemImage: String
    let severity: Severity
    let metrics: [MetricsProjection.Metric]
    let notes: [String]
    let timestamp: Date
    let unavailableReason: String?
}
