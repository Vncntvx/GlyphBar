import Foundation

enum NotesQuickStateStore {
    static func encode(_ notes: [NotesQuickModule.Note]) -> Data? {
        try? JSONEncoder().encode(notes)
    }

    static func decode(_ data: Data) -> [NotesQuickModule.Note] {
        if let notes = try? JSONDecoder().decode([NotesQuickModule.Note].self, from: data) {
            return notes
        }

        if let oldNotes = try? JSONDecoder().decode([NoteV1].self, from: data) {
            return oldNotes.map { old in
                NotesQuickModule.Note(
                    id: old.id,
                    title: old.text,
                    content: "",
                    isPinned: old.isPinned,
                    isComplete: old.isComplete,
                    createdAt: old.createdAt,
                    updatedAt: old.createdAt
                )
            }
        }

        return []
    }

    private struct NoteV1: Codable {
        let id: UUID
        var text: String
        var isPinned: Bool
        var isComplete: Bool
        let createdAt: Date
    }
}
