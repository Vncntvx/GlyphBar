import SwiftUI

struct NotesPanel: View {
    let notes: [NotesQuickModule.Note]
    var onAction: (String, Command.ActionPayload?) -> Void

    @State private var searchText = ""
    @State private var showCompleted = false
    @State private var editingNoteID: UUID?
    @State private var editTitle = ""
    @State private var editContent = ""
    @State private var newNoteText = ""

    private var pinnedNotes: [NotesQuickModule.Note] {
        notes.filter { $0.isPinned && !$0.isComplete }
    }

    private var recentNotes: [NotesQuickModule.Note] {
        notes.filter { !$0.isPinned && !$0.isComplete }
    }

    private var completedNotes: [NotesQuickModule.Note] {
        notes.filter(\.isComplete)
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    private var searchResults: [NotesQuickModule.Note] {
        guard isSearching else { return [] }
        return notes.filter { note in
            (showCompleted || !note.isComplete)
            && (note.title.localizedStandardContains(searchText)
                || note.content.localizedStandardContains(searchText))
        }
    }

    var body: some View {
        noteList
            .safeAreaInset(edge: .bottom) {
                addNoteBar
            }
    }

    private var addNoteBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                TextField("Add a note…", text: $newNoteText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addNote)

                Button(action: addNote) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(trimmedNewNoteText.isEmpty)

                Menu {
                    Toggle("Show Completed", isOn: $showCompleted)
                    Divider()
                    Button("Clear Completed", role: .destructive) {
                        onAction("clearCompleted", nil)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
            }
            .padding(10)
            .background(.thinMaterial)
        }
    }

    @ViewBuilder
    private var noteList: some View {
        if notes.isEmpty {
            GlyphEmptyStateView(
                title: "No Notes",
                subtitle: "Type below to add your first note.",
                systemImage: "note.text"
            )
            .frame(maxHeight: .infinity)
        } else if isSearching {
            searchList
        } else {
            groupedList
        }
    }

    @ViewBuilder
    private var searchList: some View {
        if searchResults.isEmpty {
            GlyphEmptyStateView(
                title: "No matches",
                subtitle: "Try a different search term.",
                systemImage: "magnifyingglass"
            )
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(searchResults) { note in
                    noteRowWithMenu(note)
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var groupedList: some View {
        List {
            if !pinnedNotes.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedNotes) { note in
                        noteRowWithMenu(note)
                    }
                }
            }

            if !recentNotes.isEmpty || (pinnedNotes.isEmpty && completedNotes.isEmpty) {
                Section("Recent") {
                    ForEach(recentNotes) { note in
                        noteRowWithMenu(note)
                    }
                }
            }

            if showCompleted && !completedNotes.isEmpty {
                Section("Completed") {
                    ForEach(completedNotes) { note in
                        noteRowWithMenu(note)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search notes…")
    }

    @ViewBuilder
    private func noteRowWithMenu(_ note: NotesQuickModule.Note) -> some View {
        NotesQuickNoteRow(
            note: note,
            isEditing: editingNoteID == note.id,
            editTitle: $editTitle,
            editContent: $editContent,
            onToggleComplete: { onAction("toggleComplete", .init(text: note.id.uuidString)) },
            onTogglePin: { onAction("togglePin", .init(text: note.id.uuidString)) },
            onCopy: { onAction("copyNote", .init(text: note.id.uuidString)) },
            onEdit: { startEditing(note) },
            onCommitEdit: { commitEditing() },
            onCancelEdit: { cancelEditing() },
            onDelete: { onAction("deleteNote", .init(text: note.id.uuidString)) }
        )
        .contextMenu { noteContextMenu(note) }
    }

    @ViewBuilder
    private func noteContextMenu(_ note: NotesQuickModule.Note) -> some View {
        Button {
            onAction("togglePin", .init(text: note.id.uuidString))
        } label: {
            Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
        }

        Button {
            onAction("copyNote", .init(text: note.id.uuidString))
        } label: {
            Label("Copy Text", systemImage: "doc.on.doc")
        }

        Button {
            startEditing(note)
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            onAction("deleteNote", .init(text: note.id.uuidString))
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var trimmedNewNoteText: String {
        newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addNote() {
        guard !trimmedNewNoteText.isEmpty else { return }
        onAction("addNote", .init(text: newNoteText))
        newNoteText = ""
    }

    private func startEditing(_ note: NotesQuickModule.Note) {
        editingNoteID = note.id
        editTitle = note.title
        editContent = note.content
    }

    private func commitEditing() {
        guard let id = editingNoteID else { return }
        let edits: [String: String] = ["title": editTitle, "content": editContent]
        let data = try? JSONEncoder().encode(edits)
        onAction("editNote", .init(text: id.uuidString, data: data))
        cancelEditing()
    }

    private func cancelEditing() {
        editingNoteID = nil
        editTitle = ""
        editContent = ""
    }
}
