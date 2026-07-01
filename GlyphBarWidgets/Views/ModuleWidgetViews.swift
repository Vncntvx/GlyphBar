import SwiftUI
import WidgetKit

struct ModuleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ModuleWidgetEntry

    var body: some View {
        let sections = WidgetContentSections(
            snapshot: entry.snapshot,
            metricLimit: family == .systemSmall ? 2 : 4,
            noteLimit: family == .systemSmall ? 2 : 4
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: entry.snapshot.symbol)
                    .font(.headline)
                    .symbolRenderingMode(.hierarchical)
                Spacer()
                WidgetStatusBadge(severity: entry.snapshot.severity)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.snapshot.title)
                    .font(family == .systemSmall ? .headline : .title3.weight(.semibold))
                    .lineLimit(2)
                Text(entry.snapshot.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let reason = sections.unavailableReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                contentSections(sections)
            }

            Spacer(minLength: 0)
        }
        .containerBackground(.regularMaterial, for: .widget)
        .widgetURL(URL(string: "glyphbar://module/\(entry.moduleID)"))
    }

    @ViewBuilder
    private func contentSections(_ sections: WidgetContentSections) -> some View {
        if !sections.metrics.isEmpty {
            VStack(spacing: 4) {
                ForEach(sections.metrics) { metric in
                    WidgetMetricRow(metric: metric)
                }
            }
        }

        if !sections.notes.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(sections.notes, id: \.self) { note in
                    Text(note)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
    }
}
