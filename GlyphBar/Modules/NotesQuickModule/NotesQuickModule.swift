import Foundation
import SwiftUI

@MainActor
final class NotesQuickModule: StatusModule, TypedModuleContribution {
    struct Note: Identifiable, Codable, Hashable {
        let id: UUID
        var text: String
        var isPinned: Bool
        var isComplete: Bool
        let createdAt: Date

        init(id: UUID = UUID(), text: String, isPinned: Bool = false, isComplete: Bool = false, createdAt: Date = Date()) {
            self.id = id
            self.text = text
            self.isPinned = isPinned
            self.isComplete = isComplete
            self.createdAt = createdAt
        }
    }

    private var notes: [Note] {
        didSet { persistState() }
    }

    // P1.13: capabilities injected at init time (no UserDefaults.standard).
    private let settings: ModuleSettingsNamespace?
    private let cache: ModuleCacheNamespace?

    init(
        settings: ModuleSettingsNamespace? = nil,
        cache: ModuleCacheNamespace? = nil
    ) {
        self.settings = settings
        self.cache = cache
        self.notes = Self.loadState(from: settings) ?? []
    }

    var manifest: ModuleManifest {
        ModuleManifest(
            id: "notesQuick",
            displayName: "Notes Quick",
            subtitle: "Pinned and recent local notes",
            systemImage: "note.text",
            version: "1.1.0",
            author: "Wenjie Xu",
            capabilities: [.statusItem, .panel, .widgets, .actions, .cachedState, .deepLinks],
            permissions: [],
            defaultRefreshPolicy: .manual,
            actions: [
                ModuleAction(id: "addNote", title: "Add Note", systemImage: "plus"),
                ModuleAction(id: "pinFirst", title: "Pin First", systemImage: "pin"),
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
    }

    // MARK: - StatusModule (legacy bridge)

    func refresh(context: ModuleContext) async throws -> ModuleSnapshot {
        buildSnapshot()
    }

    func handle(action: ModuleAction, context: ModuleContext) async throws -> ModuleEvent {
        switch action.id {
        case "addNote":
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            notes.insert(Note(
                text: "New note at \(formatter.string(from: Date()))",
                createdAt: Date()
            ), at: 0)
            return .refreshRequested(manifest.id)
        case "pinFirst":
            guard let idx = notes.firstIndex(where: { !$0.isComplete }) else { return .none }
            notes[idx].isPinned.toggle()
            return .refreshRequested(manifest.id)
        case "clearCompleted":
            notes.removeAll(where: \.isComplete)
            return .refreshRequested(manifest.id)
        default:
            return .none
        }
    }

    func makePanelView(context: ModuleContext, snapshot: ModuleSnapshot?) -> AnyView {
        AnyView(panelContent(context: PanelHostContext(moduleID: manifest.id, dispatch: { _ in })))
    }

    // MARK: - TypedModuleContribution (P1.13)

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
        case .userAction(let actionID, _):
            let action = ModuleAction(id: actionID, title: actionID, systemImage: "")
            _ = try? await handle(action: action, context: legacyContextPlaceholder)
            return DomainTransition(
                effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: buildSnapshot()))],
                health: .healthy,
                refreshProjection: true
            )
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
            snapshot: buildSnapshot(),
            notes: notes,
            onAdd: { [weak self] text in self?.addNote(text: text); context.dispatch(.refresh(reason: .manual)) },
            onToggleComplete: { [weak self] id in self?.toggleComplete(id: id); context.dispatch(.refresh(reason: .manual)) },
            onTogglePin: { [weak self] id in self?.togglePin(id: id); context.dispatch(.refresh(reason: .manual)) },
            onDelete: { [weak self] id in self?.deleteNote(id: id); context.dispatch(.refresh(reason: .manual)) },
            onClearCompleted: { [weak self] in self?.clearCompleted(); context.dispatch(.refresh(reason: .manual)) }
        )
    }

    // MARK: - Internals

    private var legacyContextPlaceholder: ModuleContext {
        ModuleContext(
            logger: GlyphLogger(),
            cacheStore: CacheStore(),
            secureStore: SecureStore(),
            permissionCenter: PermissionCenter(),
            settingsStore: AppSettingsStore(),
            platformActions: PlatformActions(),
            widgetBridge: WidgetDataBridge()
        )
    }

    private func addNote(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        notes.insert(Note(text: text.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: Date()), at: 0)
    }

    private func toggleComplete(id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].isComplete.toggle()
    }

    private func togglePin(id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].isPinned.toggle()
    }

    private func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
    }

    private func clearCompleted() {
        notes.removeAll(where: \.isComplete)
    }

    private func buildSnapshot() -> ModuleSnapshot {
        let activeNotes = notes.filter { !$0.isComplete }
        let pinnedCount = activeNotes.filter(\.isPinned).count

        let sorted = activeNotes.sorted { lhs, rhs in
            if lhs.isPinned == rhs.isPinned {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.isPinned && !rhs.isPinned
        }

        let displayNotes: [String] = sorted.prefix(8).map { note in
            let pin = note.isPinned ? "📌 " : ""
            return "\(pin)\(note.text)"
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

    // MARK: - Persistence (via capabilities)

    private static let stateKey = "moduleState"

    private func persistState() {
        settings?.set(notes, forKey: Self.stateKey)
    }

    private static func loadState(from settings: ModuleSettingsNamespace?) -> [Note]? {
        settings?.get([Note].self, forKey: stateKey)
    }
}

private struct NotesPanel: View {
    let snapshot: ModuleSnapshot?
    let notes: [NotesQuickModule.Note]
    var onAdd: (String) -> Void
    var onToggleComplete: (UUID) -> Void
    var onTogglePin: (UUID) -> Void
    var onDelete: (UUID) -> Void
    var onClearCompleted: () -> Void

    @State private var newNoteText: String = ""
    @State private var searchText: String = ""
    @State private var showCompleted: Bool = false

    private var activeNotes: [NotesQuickModule.Note] {
        notes.filter { showCompleted || !$0.isComplete }
    }

    private var filteredNotes: [NotesQuickModule.Note] {
        if searchText.isEmpty { return activeNotes }
        return activeNotes.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search notes…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.thinMaterial)

            Divider()

            // Notes list
            if filteredNotes.isEmpty && !notes.isEmpty {
                GlyphEmptyStateView(
                    title: "No matches",
                    subtitle: "Try a different search term.",
                    systemImage: "magnifyingglass"
                )
                .frame(height: 200)
            } else if notes.isEmpty {
                GlyphEmptyStateView(
                    title: "No Notes",
                    subtitle: "Type below to add your first note.",
                    systemImage: "note.text"
                )
                .frame(height: 200)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredNotes) { note in
                            NoteCard(
                                note: note,
                                onToggleComplete: { onToggleComplete(note.id) },
                                onTogglePin: { onTogglePin(note.id) },
                                onDelete: { onDelete(note.id) }
                            )
                        }
                    }
                    .padding(10)
                }
            }

            Divider()

            // Bottom bar
            HStack(spacing: 8) {
                TextField("Add a note…", text: $newNoteText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        onAdd(newNoteText)
                        newNoteText = ""
                    }

                Button(action: {
                    onAdd(newNoteText)
                    newNoteText = ""
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Menu {
                    Toggle("Show Completed", isOn: $showCompleted)
                    Divider()
                    Button("Clear Completed", role: .destructive, action: onClearCompleted)
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
}

private struct NoteCard: View {
    let note: NotesQuickModule.Note
    var onToggleComplete: () -> Void
    var onTogglePin: () -> Void
    var onDelete: () -> Void

    var body: some View {
        GlyphCard {
            HStack(spacing: 10) {
                // Complete toggle
                Button(action: onToggleComplete) {
                    Image(systemName: note.isComplete ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(note.isComplete ? .green : .secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.text)
                        .font(.callout)
                        .strikethrough(note.isComplete)
                        .foregroundStyle(note.isComplete ? .secondary : .primary)
                    Text(note.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Pin toggle
                Button(action: onTogglePin) {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                        .font(.caption)
                        .foregroundStyle(note.isPinned ? .orange : .secondary)
                }
                .buttonStyle(.plain)

                // Delete
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
