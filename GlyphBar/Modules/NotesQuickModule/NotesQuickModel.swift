import Foundation

extension NotesQuickModule {
    struct Note: Identifiable, Codable, Hashable {
        let id: UUID
        var title: String
        var content: String
        var isPinned: Bool
        var isComplete: Bool
        let createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            title: String,
            content: String = "",
            isPinned: Bool = false,
            isComplete: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.title = title
            self.content = content
            self.isPinned = isPinned
            self.isComplete = isComplete
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}
