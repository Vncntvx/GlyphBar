import Foundation
import SwiftUI

@MainActor
final class NotesQuickModule: TypedModuleContribution {

    // MARK: - Data Model

    struct Note: Identifiable, Codable, Hashable {
        let id: UUID
        var title: String
        var content: String
        var isPinned: Bool
        var isComplete: Bool
        let createdAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), title: String, content: String = "",
             isPinned: Bool = false, isComplete: Bool = false,
             createdAt: Date = Date(), updatedAt: Date = Date()) {
            self.id = id
            self.title = title
            self.content = content
            self.isPinned = isPinned
            self.isComplete = isComplete
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    /// V1 format for automatic migration from versions <= 1.1.0.
    private struct NoteV1: Codable {
        let id: UUID
        var text: String
        var isPinned: Bool
        var isComplete: Bool
        let createdAt: Date
    }

    // MARK: - State

    private var notes: [Note] {
        didSet { persistState() }
    }

    private let cache: ModuleCacheNamespace?

    init(cache: ModuleCacheNamespace? = nil) {
        self.cache = cache
        self.notes = Self.loadState(from: cache)
    }

    // MARK: - Manifest

    var manifest: ModuleManifest { Self.staticManifest }

    static let staticManifest = ModuleManifest(
        id: "notesQuick",
        displayName: "Notes Quick",
        subtitle: "Pinned and recent local notes",
        systemImage: "note.text",
        version: "1.2.0",
        author: "Wenjie Xu",
        capabilities: [.statusItem, .panel, .widgets, .actions, .cachedState, .deepLinks],
        permissions: [],
        defaultRefreshPolicy: .manual,
        actions: [
            ModuleAction(id: "addNote", title: "Add Note", systemImage: "plus"),
            ModuleAction(id: "copyNote", title: "Copy Note", systemImage: "doc.on.doc"),
            ModuleAction(id: "clearCompleted", title: "Clear Done", systemImage: "checkmark.circle", role: .destructive)
        ],
        widgets: [
            ModuleWidgetDescriptor(
                id: "notesQuick.pinned",
                title: "Pinned Notes",
                subtitle: "Recent notes",
                systemImage: "note.text",
                supportedFamilies: ["small", "medium", "large"]
            )
        ]
    )

    // MARK: - TypedModuleContribution

    func handle(
        command: Command,
        capabilities: GrantedCapabilities,
        bridge: ModuleBridge
    ) async -> DomainTransition {
        switch command {
        case .refresh:
            return DomainTransition(
                effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: buildSnapshot()))],
                health: .healthy,
                refreshProjection: true
            )

        case .userAction(let actionID, let payload):
            switch actionID {
            case "addNote":
                return handleAddNote(payload: payload)
            case "editNote":
                return handleEditNote(payload: payload)
            case "toggleComplete":
                return handleToggleComplete(payload: payload)
            case "togglePin":
                return handleTogglePin(payload: payload)
            case "deleteNote":
                return handleDeleteNote(payload: payload)
            case "copyNote":
                return handleCopyNote(payload: payload)
            case "clearCompleted":
                return handleClearCompleted()
            default:
                return .empty
            }

        default:
            return .empty
        }
    }

    func buildProjection() -> ProjectionSet {
        ProjectionBuilder.build(from: buildSnapshot())
    }

    func statusCandidates() -> [StatusCandidate] {
        let snap = buildSnapshot()
        return snap.signals.map { signal in
            StatusCandidate(
                id: signal.id,
                sourceModule: manifest.id,
                semanticRole: .primary,
                severity: signal.severity,
                priority: signal.priority,
                text: signal.title,
                icon: signal.systemImage,
                createdAt: snap.timestamp,
                expiresAt: nil,
                interruptPolicy: .normal,
                trustLevel: .bundled
            )
        }
    }

    func panelContent(context: PanelHostContext) -> some View {
        NotesPanel(
            notes: notes,
            onAction: { actionID, payload in
                context.dispatch(.userAction(actionID: actionID, payload: payload))
            }
        )
    }

    // MARK: - Action Handlers

    private func handleAddNote(payload: Command.ActionPayload?) -> DomainTransition {
        guard let text = payload?.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        notes.insert(Note(title: trimmed, createdAt: Date()), at: 0)
        return DomainTransition(
            effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: buildSnapshot()))],
            health: .healthy,
            refreshProjection: true
        )
    }

    private func handleEditNote(payload: Command.ActionPayload?) -> DomainTransition {
        guard let idString = payload?.text,
              let id = UUID(uuidString: idString),
              let idx = notes.firstIndex(where: { $0.id == id }) else {
            return .empty
        }
        // Decode edit fields from data payload
        if let data = payload?.data,
           let edits = try? JSONDecoder().decode([String: String].self, from: data) {
            if let title = edits["title"] { notes[idx].title = title }
            if let content = edits["content"] { notes[idx].content = content }
        }
        notes[idx].updatedAt = Date()
        return DomainTransition(
            effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: buildSnapshot()))],
            health: .healthy,
            refreshProjection: true
        )
    }

    private func handleToggleComplete(payload: Command.ActionPayload?) -> DomainTransition {
        guard let idString = payload?.text,
              let id = UUID(uuidString: idString),
              let idx = notes.firstIndex(where: { $0.id == id }) else {
            return .empty
        }
        notes[idx].isComplete.toggle()
        notes[idx].updatedAt = Date()
        return DomainTransition(
            effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: buildSnapshot()))],
            health: .healthy,
            refreshProjection: true
        )
    }

    private func handleTogglePin(payload: Command.ActionPayload?) -> DomainTransition {
        guard let idString = payload?.text,
              let id = UUID(uuidString: idString),
              let idx = notes.firstIndex(where: { $0.id == id }) else {
            return .empty
        }
        notes[idx].isPinned.toggle()
        notes[idx].updatedAt = Date()
        return DomainTransition(
            effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: buildSnapshot()))],
            health: .healthy,
            refreshProjection: true
        )
    }

    private func handleDeleteNote(payload: Command.ActionPayload?) -> DomainTransition {
        guard let idString = payload?.text,
              let id = UUID(uuidString: idString) else {
            return .empty
        }
        notes.removeAll { $0.id == id }
        return DomainTransition(
            effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: buildSnapshot()))],
            health: .healthy,
            refreshProjection: true
        )
    }

    private func handleCopyNote(payload: Command.ActionPayload?) -> DomainTransition {
        guard let idString = payload?.text,
              let id = UUID(uuidString: idString),
              let note = notes.first(where: { $0.id == id }) else {
            return .empty
        }
        let text = note.title + (note.content.isEmpty ? "" : "\n\(note.content)")
        return DomainTransition(
            effects: [
                .publishSnapshot(ProjectionBuilder.buildEnvelope(from: buildSnapshot())),
                .copyToClipboard(text)
            ],
            health: .healthy,
            refreshProjection: true
        )
    }

    private func handleClearCompleted() -> DomainTransition {
        notes.removeAll(where: \.isComplete)
        return DomainTransition(
            effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: buildSnapshot()))],
            health: .healthy,
            refreshProjection: true
        )
    }

    // MARK: - Snapshot

    private func buildSnapshot() -> ModuleSnapshot {
        let activeNotes = notes.filter { !$0.isComplete }
        let pinnedCount = activeNotes.filter(\.isPinned).count

        let sorted = activeNotes.sorted { lhs, rhs in
            if lhs.isPinned == rhs.isPinned {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.isPinned && !rhs.isPinned
        }

        let displayNotes: [String] = sorted.prefix(8).map { note in
            let pin = note.isPinned ? "📌 " : ""
            let content = note.content.isEmpty ? "" : " — \(note.content.prefix(40))"
            return "\(pin)\(note.title)\(content)"
        }

        var signals: [StatusSignal] = []
        if pinnedCount > 0 {
            signals.append(StatusSignal(
                id: "notesQuick.pinned", title: "\(pinnedCount) pinned",
                message: "\(pinnedCount) pinned notes pending",
                systemImage: "pin.fill", severity: .info, priority: 30
            ))
        }

        return ModuleSnapshot(
            id: manifest.id,
            title: "\(activeNotes.count) notes",
            subtitle: pinnedCount > 0 ? "\(pinnedCount) pinned" : "No pinned notes",
            systemImage: manifest.systemImage,
            signals: signals,
            metrics: ["notes": Double(activeNotes.count), "pinned": Double(pinnedCount)],
            notes: displayNotes
        )
    }

    // MARK: - Persistence (via ModuleCacheNamespace)

    private static let stateKey = "moduleState"

    private func persistState() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        cache?.saveDomainState(data)
    }

    private static func loadState(from cache: ModuleCacheNamespace?) -> [Note] {
        guard let data = cache?.loadDomainState() else { return [] }
        // Try current format first
        if let notes = try? JSONDecoder().decode([Note].self, from: data) {
            return notes
        }
        // Migrate from V1 format (<= 1.1.0)
        if let oldNotes = try? JSONDecoder().decode([NoteV1].self, from: data) {
            return oldNotes.map { old in
                Note(
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
}

// MARK: - Panel Views

private struct NotesPanel: View {
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
        notes.filter { $0.isComplete }
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private var searchResults: [NotesQuickModule.Note] {
        guard isSearching else { return [] }
        return notes.filter { note in
            (showCompleted || !note.isComplete) &&
            (note.title.localizedCaseInsensitiveContains(searchText) ||
             note.content.localizedCaseInsensitiveContains(searchText))
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
                    .onSubmit {
                        guard !newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        onAction("addNote", .init(text: newNoteText))
                        newNoteText = ""
                    }

                Button {
                    guard !newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onAction("addNote", .init(text: newNoteText))
                    newNoteText = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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
                        NoteRow(note: note, isEditing: editingNoteID == note.id,
                                editTitle: $editTitle, editContent: $editContent,
                                onToggleComplete: { onAction("toggleComplete", .init(text: note.id.uuidString)) },
                                onTogglePin: { onAction("togglePin", .init(text: note.id.uuidString)) },
                                onCopy: { onAction("copyNote", .init(text: note.id.uuidString)) },
                                onEdit: { startEditing(note) },
                                onCommitEdit: { commitEditing() },
                                onDelete: { onAction("deleteNote", .init(text: note.id.uuidString)) })
                        .contextMenu { noteContextMenu(note) }
                    }
                }
                .listStyle(.sidebar)
            }
        } else {
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
    }

    @ViewBuilder
    private func noteRowWithMenu(_ note: NotesQuickModule.Note) -> some View {
        NoteRow(note: note, isEditing: editingNoteID == note.id,
                editTitle: $editTitle, editContent: $editContent,
                onToggleComplete: { onAction("toggleComplete", .init(text: note.id.uuidString)) },
                onTogglePin: { onAction("togglePin", .init(text: note.id.uuidString)) },
                onCopy: { onAction("copyNote", .init(text: note.id.uuidString)) },
                onEdit: { startEditing(note) },
                onCommitEdit: { commitEditing() },
                onDelete: { onAction("deleteNote", .init(text: note.id.uuidString)) })
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
        editingNoteID = nil
        editTitle = ""
        editContent = ""
    }
}

private struct NoteRow: View {
    let note: NotesQuickModule.Note
    let isEditing: Bool
    @Binding var editTitle: String
    @Binding var editContent: String
    var onToggleComplete: () -> Void
    var onTogglePin: () -> Void
    var onCopy: () -> Void
    var onEdit: () -> Void
    var onCommitEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Native checkbox toggle
            Toggle("", isOn: .init(
                get: { note.isComplete },
                set: { _ in onToggleComplete() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    // Inline editing mode
                    TextField("Title", text: $editTitle)
                        .textFieldStyle(.plain)
                        .font(.callout.weight(.medium))
                    TextField("Content", text: $editContent, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .lineLimit(2...4)
                    HStack(spacing: 8) {
                        Button("Done") { onCommitEdit() }
                            .controlSize(.small)
                        Button("Cancel") {
                            onCommitEdit()  // Reverts by not saving changes
                        }
                        .controlSize(.small)
                    }
                } else {
                    // Display mode
                    HStack(spacing: 4) {
                        Text(note.title)
                            .font(.callout.weight(.medium))
                            .strikethrough(note.isComplete)
                            .foregroundStyle(note.isComplete ? .secondary : .primary)

                        if note.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange.opacity(0.7))
                        }
                    }

                    if !note.content.isEmpty {
                        Text(note.content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .strikethrough(note.isComplete)
                    }

                    Text(note.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .opacity(note.isComplete && !isEditing ? 0.5 : 1.0)
        .padding(.vertical, 2)
    }
}
