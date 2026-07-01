import SwiftUI

struct DeclarativeModulePanel: View {
    let manifest: ModuleManifest
    let descriptor: ExternalPanelDescriptor?
    let snapshot: ModuleSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !orderedMetrics.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    ForEach(orderedMetrics, id: \.0) { key, value in
                        GlyphMetricCard(title: key.capitalized, value: formatted(value), systemImage: "chart.bar")
                    }
                }
            }

            if let notes = snapshot?.notes, !notes.isEmpty {
                GlyphCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(descriptor?.noteTitle ?? "Notes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(notes, id: \.self) { note in
                            Text(note)
                                .font(.callout)
                                .lineLimit(2)
                        }
                    }
                }
            }

            if !orderedMetadata.isEmpty {
                GlyphCard {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(orderedMetadata, id: \.0) { key, value in
                            HStack {
                                Text(key.capitalized)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(value)
                                    .textSelection(.enabled)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private var orderedMetrics: [(String, Double)] {
        let metrics = snapshot?.metrics ?? [:]
        if let order = descriptor?.metricOrder, !order.isEmpty {
            return order.compactMap { key in
                metrics[key].map { (key, $0) }
            }
        }
        return metrics.sorted { $0.key < $1.key }
    }

    private var orderedMetadata: [(String, String)] {
        let metadata = snapshot?.metadata ?? [:]
        if let keys = descriptor?.metadataKeys, !keys.isEmpty {
            return keys.compactMap { key in
                metadata[key].map { (key, $0) }
            }
        }
        return metadata.sorted { $0.key < $1.key }
    }

    private func formatted(_ value: Double) -> String {
        if value.rounded() == value {
            return Int(value).formatted()
        }
        return value.formatted(.number.precision(.fractionLength(1)))
    }
}
