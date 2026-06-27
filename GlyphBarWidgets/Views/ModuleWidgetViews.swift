import SwiftUI
import WidgetKit

struct ModuleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ModuleWidgetEntry

    var body: some View {
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

            if let reason = entry.snapshot.unavailableReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if !entry.snapshot.metrics.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(entry.snapshot.metrics.prefix(family == .systemSmall ? 2 : 4))) { metric in
                        WidgetMetricRow(metric: metric)
                    }
                }
            } else if !entry.snapshot.notes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(entry.snapshot.notes.prefix(family == .systemSmall ? 2 : 4)), id: \.self) { note in
                        Text(note)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .containerBackground(.regularMaterial, for: .widget)
        .widgetURL(URL(string: "glyphbar://module/\(entry.moduleID)"))
    }
}
