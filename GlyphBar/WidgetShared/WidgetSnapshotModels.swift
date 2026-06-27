import Foundation

enum WidgetSeverity: String, Codable, Sendable {
    case normal
    case info
    case warning
    case critical
}

struct WidgetMetric: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var value: String
    var symbol: String
}

struct WidgetModuleSnapshot: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var subtitle: String
    var symbol: String
    var severity: WidgetSeverity
    var metrics: [WidgetMetric]
    var notes: [String]
    var timestamp: Date
    var unavailableReason: String?

    var isAvailable: Bool {
        unavailableReason == nil
    }
}
