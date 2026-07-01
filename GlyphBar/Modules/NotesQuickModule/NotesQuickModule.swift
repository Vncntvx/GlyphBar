import Foundation
import SwiftUI

@MainActor
final class NotesQuickModule: TypedModuleContribution {

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
        notes.insert(Note(title: trimmed, createdAt: .now), at: 0)
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
        notes[idx].updatedAt = .now
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
        notes[idx].updatedAt = .now
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
        notes[idx].updatedAt = .now
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

    private func persistState() {
        guard let data = NotesQuickStateStore.encode(notes) else { return }
        cache?.saveDomainState(data)
    }

    private static func loadState(from cache: ModuleCacheNamespace?) -> [Note] {
        guard let data = cache?.loadDomainState() else { return [] }
        return NotesQuickStateStore.decode(data)
    }
}
