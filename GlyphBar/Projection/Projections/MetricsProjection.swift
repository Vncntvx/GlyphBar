import Foundation

/// Numeric metrics list (e.g. CPU %, balance, counter value).
struct MetricsProjection: Sendable {
    let metrics: [Metric]

    struct Metric: Sendable, Identifiable {
        let id: String
        let label: String
        let value: Double
        let unit: String
        let systemImage: String?
    }
}
