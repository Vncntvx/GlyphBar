import Foundation

/// Panel content model — a Codable description of the panel layout. P1 keeps
/// this simple (text/metric/chart/list/action); P3 may let modules vend their
/// own SwiftUI views via `TypedModuleContribution.panelContent`.
struct PanelModelProjection: Sendable, Codable {
    let schemaVersion: Int
    let elements: [Element]

    enum Element: Sendable, Codable {
        case text(String)
        case metric(id: String, label: String, value: String, systemImage: String?)
        case chart(ChartProjection)
        case list(ListProjection)
        case action(id: String, title: String, systemImage: String?)
    }
}
