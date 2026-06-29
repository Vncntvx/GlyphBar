import Foundation

/// Builds `ProjectionSet` / `SnapshotEnvelope` from the legacy `ModuleSnapshot`
/// shape. P1.13 replaces this with per-module `buildProjection()` methods on
/// `ModuleContract`; this enum is the bridge.
@MainActor
enum ProjectionBuilder {
    static func build(from snapshot: ModuleSnapshot, health: ModuleHealth = .healthy) -> ProjectionSet {
        let summary = SummaryProjection(
            title: snapshot.title,
            subtitle: snapshot.subtitle,
            systemImage: snapshot.systemImage
        )

        let metrics = MetricsProjection(
            metrics: snapshot.metrics
                .sorted { $0.key < $1.key }
                .map { MetricsProjection.Metric(
                    id: $0.key,
                    label: $0.key.capitalized,
                    value: $0.value,
                    unit: "",
                    systemImage: "chart.bar"
                ) }
        )

        let list = ListProjection(
            items: snapshot.notes.indices.map { index in
                ListProjection.Item(
                    id: "note-\(index)",
                    title: snapshot.notes[index],
                    subtitle: nil,
                    systemImage: nil,
                    severity: nil
                )
            }
        )

        let topSeverity = snapshot.signals.map(\.severity).max() ?? .normal
        let widget = WidgetProjection(
            title: snapshot.title,
            subtitle: snapshot.subtitle,
            systemImage: snapshot.systemImage,
            severity: topSeverity,
            metrics: metrics.metrics,
            notes: snapshot.notes,
            timestamp: snapshot.timestamp,
            unavailableReason: {
                if case .unavailable(let reason) = snapshot.freshness {
                    return reason
                }
                return nil
            }()
        )

        let candidates = snapshot.signals.map { signal in
            StatusCandidate(
                id: signal.id,
                sourceModule: snapshot.id,
                semanticRole: .primary,
                severity: signal.severity,
                priority: signal.priority,
                text: signal.title,
                icon: signal.systemImage,
                createdAt: snapshot.timestamp,
                expiresAt: nil,
                interruptPolicy: .normal,
                trustLevel: .bundled
            )
        }

        return ProjectionSet(
            summary: summary,
            metrics: metrics,
            list: list,
            chart: nil,
            statusCandidates: candidates,
            widget: widget,
            panelModel: nil
        )
    }

    static func buildEnvelope(
        from snapshot: ModuleSnapshot,
        health: ModuleHealth = .healthy,
        validUntil: Date? = nil
    ) -> SnapshotEnvelope {
        SnapshotEnvelope(
            id: snapshot.id,
            schemaVersion: 1,
            capturedAt: snapshot.timestamp,
            validUntil: validUntil,
            freshness: snapshot.freshness,
            health: health,
            projections: build(from: snapshot, health: health)
        )
    }

    /// Reconstructs a `ModuleSnapshot` from a `SnapshotEnvelope`.
    /// Used by `ModuleRuntime` to maintain the legacy `snapshots` dictionary
    /// and `CacheStore`/`WidgetDataBridge` paths during the transition.
    static func buildSnapshot(from envelope: SnapshotEnvelope) -> ModuleSnapshot {
        let projections = envelope.projections
        let metrics: [String: Double] = Dictionary(
            uniqueKeysWithValues: projections.metrics?.metrics.map { ($0.id, $0.value) } ?? []
        )
        let notes: [String] = projections.list?.items.map(\.title) ?? []
        let metadata: [String: String] = [:]

        var signals: [StatusSignal] = []
        if let summary = projections.summary {
            // Reconstruct primary signal from summary
        }
        for candidate in projections.statusCandidates {
            signals.append(StatusSignal(
                id: candidate.id,
                title: candidate.text,
                message: "",
                systemImage: candidate.icon,
                severity: candidate.severity,
                priority: candidate.priority
            ))
        }

        return ModuleSnapshot(
            id: envelope.id,
            title: projections.summary?.title ?? "",
            subtitle: projections.summary?.subtitle ?? "",
            systemImage: projections.summary?.systemImage ?? "circle",
            timestamp: envelope.capturedAt,
            freshness: envelope.freshness,
            signals: signals,
            metrics: metrics,
            notes: notes,
            metadata: metadata
        )
    }
}
