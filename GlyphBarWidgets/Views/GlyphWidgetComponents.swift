import SwiftUI
import WidgetKit

struct WidgetStatusBadge: View {
    let severity: WidgetSeverity

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .font(.caption.weight(.semibold))
    }

    private var symbol: String {
        switch severity {
        case .normal: return "checkmark.circle"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "exclamationmark.octagon"
        }
    }

    private var color: Color {
        switch severity {
        case .normal: return .green
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

struct WidgetMetricRow: View {
    let metric: WidgetMetric

    var body: some View {
        HStack {
            Label(metric.title, systemImage: metric.symbol)
                .lineLimit(1)
            Spacer()
            Text(metric.value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
