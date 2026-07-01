import Foundation
import Testing
@testable import GlyphBar

// MARK: - Test Helpers

/// Minimal ModuleBridge that records submitted effects for assertions.
@MainActor
final class MockModuleBridge: ModuleBridge {
    private(set) var submittedEffects: [Effect] = []

    func submit(_ effects: [Effect]) {
        submittedEffects.append(contentsOf: effects)
    }

    func submit(_ effect: Effect) {
        submittedEffects.append(effect)
    }
}

// MARK: - NotesQuickModule Tests

@MainActor
struct NotesQuickModuleTests {

    // MARK: - addNote

    @Test("addNote 创建新笔记并发布快照")
    func addNoteCreatesNoteAndPublishesSnapshot() async {
        let module = makeModule()
        let result = await module.handle(
            command: .userAction(actionID: "addNote", payload: .init(text: "买牛奶")),
            capabilities: makeCapabilities(),
            bridge: MockModuleBridge()
        )
        #expect(result.effects.contains(where: { if case .publishSnapshot = $0 { true } else { false } }))
        #expect(result.refreshProjection == true)
    }

    @Test("addNote 忽略空白文本")
    func addNoteIgnoresEmptyText() async {
        let module = makeModule()
        let result = await module.handle(
            command: .userAction(actionID: "addNote", payload: .init(text: "   ")),
            capabilities: makeCapabilities(),
            bridge: MockModuleBridge()
        )
        #expect(result.effects.isEmpty)
        #expect(result.refreshProjection == false)
    }

    // MARK: - editNote

    @Test("editNote 更新标题和内容")
    func editNoteUpdatesTitleAndContent() async {
        let noteID = UUID()
        let cache = makeCache()
        // Write a note directly into cache for the module to load
        let note = NotesQuickModule.Note(id: noteID, title: "旧标题", content: "旧内容", createdAt: Date())
        let data = try! JSONEncoder().encode([note])
        cache.saveDomainState(data)
        let module = NotesQuickModule(cache: cache)

        let editPayload: [String: String] = ["title": "新标题", "content": "新内容"]
        let result = await module.handle(
            command: .userAction(actionID: "editNote", payload: .init(text: noteID.uuidString, data: try! JSONEncoder().encode(editPayload))),
            capabilities: makeCapabilities(cache: cache),
            bridge: MockModuleBridge()
        )
        #expect(result.effects.contains(where: { if case .publishSnapshot = $0 { true } else { false } }))
        #expect(result.refreshProjection == true)
    }

    @Test("editNote 忽略无效 ID")
    func editNoteIgnoresInvalidID() async {
        let module = makeModule()
        let editPayload: [String: String] = ["title": "新标题"]
        let result = await module.handle(
            command: .userAction(actionID: "editNote", payload: .init(text: UUID().uuidString, data: try! JSONEncoder().encode(editPayload))),
            capabilities: makeCapabilities(),
            bridge: MockModuleBridge()
        )
        #expect(result.effects.isEmpty)
        #expect(result.refreshProjection == false)
    }

    // MARK: - toggleComplete

    @Test("toggleComplete 翻转完成状态")
    func toggleCompleteFlipsState() async {
        let noteID = UUID()
        let cache = makeCache()
        let note = NotesQuickModule.Note(id: noteID, title: "Test", createdAt: Date())
        let data = try! JSONEncoder().encode([note])
        cache.saveDomainState(data)
        let module = NotesQuickModule(cache: cache)

        let result = await module.handle(
            command: .userAction(actionID: "toggleComplete", payload: .init(text: noteID.uuidString)),
            capabilities: makeCapabilities(cache: cache),
            bridge: MockModuleBridge()
        )
        #expect(result.effects.contains(where: { if case .publishSnapshot = $0 { true } else { false } }))
        #expect(result.refreshProjection == true)
    }

    // MARK: - togglePin

    @Test("togglePin 翻转置顶状态")
    func togglePinFlipsState() async {
        let noteID = UUID()
        let cache = makeCache()
        let note = NotesQuickModule.Note(id: noteID, title: "Test", createdAt: Date())
        let data = try! JSONEncoder().encode([note])
        cache.saveDomainState(data)
        let module = NotesQuickModule(cache: cache)

        let result = await module.handle(
            command: .userAction(actionID: "togglePin", payload: .init(text: noteID.uuidString)),
            capabilities: makeCapabilities(cache: cache),
            bridge: MockModuleBridge()
        )
        #expect(result.effects.contains(where: { if case .publishSnapshot = $0 { true } else { false } }))
        #expect(result.refreshProjection == true)
    }

    // MARK: - deleteNote

    @Test("deleteNote 从列表中移除笔记")
    func deleteNoteRemovesNote() async {
        let noteID = UUID()
        let cache = makeCache()
        let note = NotesQuickModule.Note(id: noteID, title: "Delete me", createdAt: Date())
        let data = try! JSONEncoder().encode([note])
        cache.saveDomainState(data)
        let module = NotesQuickModule(cache: cache)

        let result = await module.handle(
            command: .userAction(actionID: "deleteNote", payload: .init(text: noteID.uuidString)),
            capabilities: makeCapabilities(cache: cache),
            bridge: MockModuleBridge()
        )
        #expect(result.effects.contains(where: { if case .publishSnapshot = $0 { true } else { false } }))
        #expect(result.refreshProjection == true)
    }

    // MARK: - copyNote

    @Test("copyNote 返回剪贴板 Effect")
    func copyNoteReturnsClipboardEffect() async {
        let noteID = UUID()
        let cache = makeCache()
        let note = NotesQuickModule.Note(id: noteID, title: "买牛奶", content: "全脂", createdAt: Date())
        let data = try! JSONEncoder().encode([note])
        cache.saveDomainState(data)
        let module = NotesQuickModule(cache: cache)

        let result = await module.handle(
            command: .userAction(actionID: "copyNote", payload: .init(text: noteID.uuidString)),
            capabilities: makeCapabilities(cache: cache),
            bridge: MockModuleBridge()
        )
        #expect(result.effects.contains(where: {
            if case .copyToClipboard(let text) = $0 {
                return text.contains("买牛奶")
            }
            return false
        }))
    }

    // MARK: - clearCompleted

    @Test("clearCompleted 移除所有已完成笔记")
    func clearCompletedRemovesCompleted() async {
        let id1 = UUID(), id2 = UUID()
        let cache = makeCache()
        let data = try! JSONEncoder().encode([
            NotesQuickModule.Note(id: id1, title: "Active", createdAt: Date()),
            NotesQuickModule.Note(id: id2, title: "Done", isComplete: true, createdAt: Date())
        ])
        cache.saveDomainState(data)
        let module = NotesQuickModule(cache: cache)

        let result = await module.handle(
            command: .userAction(actionID: "clearCompleted", payload: nil),
            capabilities: makeCapabilities(cache: cache),
            bridge: MockModuleBridge()
        )
        #expect(result.effects.contains(where: { if case .publishSnapshot = $0 { true } else { false } }))
        #expect(result.refreshProjection == true)
    }

    // MARK: - Snapshot

    @Test("快照将置顶笔记排在前面")
    func snapshotSortsPinnedFirst() {
        let cache = makeCache()
        let data = try! JSONEncoder().encode([
            NotesQuickModule.Note(id: UUID(), title: "Recent", createdAt: Date()),
            NotesQuickModule.Note(id: UUID(), title: "Pinned", isPinned: true, createdAt: Date().addingTimeInterval(-60))
        ])
        cache.saveDomainState(data)
        let module = NotesQuickModule(cache: cache)

        let projection = module.buildProjection()
        #expect(projection.list?.items.first?.title.hasPrefix("📌") == true)
    }

    @Test("快照过滤已完成笔记")
    func snapshotFiltersCompleted() {
        let cache = makeCache()
        let data = try! JSONEncoder().encode([
            NotesQuickModule.Note(id: UUID(), title: "Active", createdAt: Date()),
            NotesQuickModule.Note(id: UUID(), title: "Done", isComplete: true, createdAt: Date())
        ])
        cache.saveDomainState(data)
        let module = NotesQuickModule(cache: cache)

        let projection = module.buildProjection()
        let noteTitles = projection.list?.items.map(\.title) ?? []
        #expect(!noteTitles.contains(where: { $0.contains("Done") }))
    }

    // MARK: - Persistence

    @Test("持久化写入和读取一致")
    func persistenceRoundTrip() {
        let cache = makeCache()
        let notes = [
            NotesQuickModule.Note(id: UUID(), title: "Note 1", content: "Content 1", createdAt: Date()),
            NotesQuickModule.Note(id: UUID(), title: "Note 2", isPinned: true, createdAt: Date())
        ]
        let data = try! JSONEncoder().encode(notes)
        cache.saveDomainState(data)

        let loaded = NotesQuickModule(cache: cache)
        let projection = loaded.buildProjection()
        #expect(projection.list?.items.count == 2)
    }

    @Test("从 V1 格式自动迁移")
    func migrationFromV1Format() {
        let cache = makeCache()
        // V1 format: only `text` field, no `title`/`content`/`updatedAt`
        struct NoteV1: Codable {
            let id: UUID
            var text: String
            var isPinned: Bool
            var isComplete: Bool
            let createdAt: Date
        }
        let v1Notes = [
            NoteV1(id: UUID(), text: "旧笔记", isPinned: true, isComplete: false, createdAt: Date())
        ]
        let data = try! JSONEncoder().encode(v1Notes)
        cache.saveDomainState(data)

        let module = NotesQuickModule(cache: cache)
        let projection = module.buildProjection()
        #expect(projection.list?.items.first?.title.contains("旧笔记") == true)
    }

    // MARK: - Unknown action

    @Test("未知动作返回 empty")
    func unknownActionReturnsEmpty() async {
        let module = makeModule()
        let result = await module.handle(
            command: .userAction(actionID: "nonexistent", payload: nil),
            capabilities: makeCapabilities(),
            bridge: MockModuleBridge()
        )
        #expect(result.effects.isEmpty)
        #expect(result.refreshProjection == false)
    }

    // MARK: - Helpers

    private func makeModule() -> NotesQuickModule {
        NotesQuickModule(cache: makeCache())
    }

    private func makeCache() -> ModuleCacheNamespace {
        let defaults = UserDefaults(suiteName: "NotesQuickTest.\(UUID().uuidString)")!
        return ModuleCacheNamespace(moduleID: "notesQuick", defaults: defaults)
    }

    private func makeCapabilities(cache: ModuleCacheNamespace? = nil) -> GrantedCapabilities {
        GrantedCapabilities(cache: cache, bridge: MockModuleBridge())
    }
}
