import Foundation

/// A list of items (e.g. notes, network interfaces, recent actions).
struct ListProjection: Sendable, Codable {
    let items: [Item]

    struct Item: Sendable, Identifiable, Codable {
        let id: String
        let title: String
        let subtitle: String?
        let systemImage: String?
        let severity: Severity?
    }
}
