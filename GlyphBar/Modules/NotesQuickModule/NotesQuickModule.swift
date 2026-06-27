import Foundation
import SwiftUI

@MainActor
final class NotesQuickModule: StatusModule {
    private struct Note: Identifiable, Codable, Hashable {
        let id: UUID
        var text: String
        var isPinned: Bool
        var isComplete: Bool
    }

    private var notes: [Note] = [
        Note(id: UUID(), text: "Review module snapshots", isPinned: true, isComplete: false),
        Note(id: UUID(), text: "Check widget cache", isPinned: false, isComplete: false)
    ]

    var manifest: ModuleManifest {
        ModuleManifest(
            id: "notesQuick",
            displayName: "Notes Quick",
            subtitle: "Pinned and recent local notes",
            systemImage: "note.text",
            version: "1.0.0",
            author: "Wenjie Xu",
            capabilities: [.panel, .widgets, .actions, .cachedState, .deepLinks],
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

    func refresh(context: ModuleContext) async throws -> ModuleSnapshot {
        let pinnedCount = notes.filter(\.isPinned).count
        let visibleNotes = notes
            .sorted { lhs, rhs in
                if lhs.isPinned == rhs.isPinned {
                    return lhs.text < rhs.text
                }
                return lhs.isPinned && !rhs.isPinned
            }
            .map { note in
                note.isPinned ? "Pinned: \(note.text)" : note.text
            }

        return ModuleSnapshot(
            id: manifest.id,
            title: "\(notes.count) notes",
            subtitle: "\(pinnedCount) pinned",
            systemImage: manifest.systemImage,
            metrics: ["notes": Double(notes.count), "pinned": Double(pinnedCount)],
            notes: Array(visibleNotes.prefix(5))
        )
    }

    func handle(action: ModuleAction, context: ModuleContext) async throws -> ModuleEvent {
        switch action.id {
        case "addNote":
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            notes.insert(Note(id: UUID(), text: "Captured at \(formatter.string(from: Date()))", isPinned: false, isComplete: false), at: 0)
            return .refreshRequested(manifest.id)
        case "pinFirst":
            guard !notes.isEmpty else { return .none }
            notes[0].isPinned.toggle()
            return .refreshRequested(manifest.id)
        case "clearCompleted":
            notes.removeAll(where: \.isComplete)
            return .refreshRequested(manifest.id)
        default:
            return .none
        }
    }

    func makePanelView(context: ModuleContext, snapshot: ModuleSnapshot?) -> AnyView {
        AnyView(NotesPanel(snapshot: snapshot))
    }
}

private struct NotesPanel: View {
    let snapshot: ModuleSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if snapshot?.notes.isEmpty != false {
                GlyphEmptyStateView(title: "No Notes", subtitle: "Add a note from the action row.", systemImage: "note.text")
                    .frame(height: 180)
            } else {
                ForEach(snapshot?.notes ?? [], id: \.self) { note in
                    GlyphCard {
                        HStack(spacing: 10) {
                            Image(systemName: note.hasPrefix("Pinned:") ? "pin.fill" : "text.alignleft")
                                .foregroundStyle(note.hasPrefix("Pinned:") ? .orange : .secondary)
                            Text(note)
                                .lineLimit(2)
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}
