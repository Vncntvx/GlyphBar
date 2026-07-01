import Foundation
import WidgetKit

/// Envelope-aware extension on `WidgetDataBridge`.
///
/// Lives in the main app target only (not the widget extension) because
/// `SnapshotEnvelope` / `ProjectionSet` / `WidgetProjection` are defined under
/// `GlyphBar/Kernel/` and `GlyphBar/Projection/`, which are not compiled into
/// the widget extension target.
///
/// Lets `EffectExecutor` publish `SnapshotEnvelope` values directly via
/// `Effect.publishSnapshot`.
extension WidgetDataBridge {
    /// Publishes an envelope's widget projection to the app group container
    /// and triggers `WidgetCenter.shared.reloadAllTimelines()`.
    func publish(_ envelope: SnapshotEnvelope) {
        let widgetSnapshot = Self.widgetSnapshot(from: envelope)
        write(widgetSnapshot, for: envelope.id)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Converts a `SnapshotEnvelope` to a `WidgetModuleSnapshot` using the
    /// envelope's `WidgetProjection`. Falls back to an unavailable snapshot
    /// if the envelope has no widget projection.
    static func widgetSnapshot(from envelope: SnapshotEnvelope) -> WidgetModuleSnapshot {
        guard let widget = envelope.projections.widget else {
            return WidgetModuleSnapshot(
                id: envelope.id,
                title: "",
                subtitle: "",
                symbol: "",
                severity: .normal,
                metrics: [],
                notes: [],
                timestamp: envelope.capturedAt,
                unavailableReason: "No widget projection"
            )
        }

        let widgetSeverity: WidgetSeverity
        switch widget.severity {
        case .normal: widgetSeverity = .normal
        case .info: widgetSeverity = .info
        case .warning: widgetSeverity = .warning
        case .critical: widgetSeverity = .critical
        }

        let metrics = widget.metrics.map { metric in
            WidgetMetric(
                id: metric.id,
                title: metric.label,
                value: formatted(metric.value),
                symbol: metric.systemImage ?? "chart.bar"
            )
        }

        return WidgetModuleSnapshot(
            id: envelope.id,
            title: widget.title,
            subtitle: widget.subtitle,
            symbol: widget.systemImage,
            severity: widgetSeverity,
            metrics: metrics,
            notes: widget.notes,
            timestamp: widget.timestamp,
            unavailableReason: widget.unavailableReason
        )
    }

    private static func formatted(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}
