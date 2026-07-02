import SwiftUI

struct NotesQuickNoteRow: View {
    let note: NotesQuickModule.Note
    let isEditing: Bool
    @Binding var editTitle: String
    @Binding var editContent: String
    var onToggleComplete: () -> Void
    var onTogglePin: () -> Void
    var onCopy: () -> Void
    var onEdit: () -> Void
    var onCommitEdit: () -> Void
    var onCancelEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: .init(
                get: { note.isComplete },
                set: { _ in onToggleComplete() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    editFields
                } else {
                    displayContent
                }
            }
        }
        .opacity(note.isComplete && !isEditing ? 0.5 : 1.0)
        .padding(.vertical, 2)
    }

    private var editFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Title", text: $editTitle)
                .textFieldStyle(.plain)
                .font(.callout.weight(.medium))
            TextField("Content", text: $editContent, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.caption)
                .lineLimit(2...4)
            HStack(spacing: 8) {
                Button("Done", action: onCommitEdit)
                    .controlSize(.small)
                Button("Cancel", action: onCancelEdit)
                    .controlSize(.small)
            }
        }
    }

    private var displayContent: some View {
        VStack(alignment: .leading, spacing: 2) {
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
