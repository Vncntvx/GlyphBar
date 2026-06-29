import Foundation

/// A chart series (e.g. usage over time, historical metrics).
struct ChartProjection: Sendable, Codable {
    let series: [Series]

    struct Series: Sendable, Identifiable, Codable {
        let id: String
        let label: String
        let color: String?
        let points: [Point]
    }

    struct Point: Sendable, Codable {
        let x: String
        let y: Double
    }
}
