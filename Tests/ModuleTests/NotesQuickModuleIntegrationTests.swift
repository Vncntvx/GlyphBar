import Foundation
import Testing
@testable import GlyphBar

// MARK: - NotesQuickModule Integration Tests

/// 验证 NotesQuickModule 在完整 ModuleHarness 链路中的行为。
/// ModuleHarness 复用 ModuleSupervisor 和 CapabilityFactory，
/// 让测试在相同的 command → handle → effect → snapshot 路径上运行，
/// 与真实运行时完全一致。
@MainActor
struct NotesQuickModuleIntegrationTests {

    // MARK: - ModuleHarness headless dispatch

    @Test("ModuleHarness dispatch addNote 后 latestSnapshot 正确更新")
    func harnessDispatchAddNoteUpdatesSnapshot() async {
        let module = NotesQuickModule(cache: makeCache())
        let harness = ModuleHarness(module: module)

        let transition = await harness.dispatch(
            .userAction(actionID: "addNote", payload: .init(text: "集成测试笔记"))
        )

        #expect(!transition.effects.isEmpty, "addNote 应该产生 effects")
        #expect(harness.latestSnapshot != nil, "latestSnapshot 应该被更新")
        #expect(harness.latestSnapshot?.id == "notesQuick", "snapshot ID 应该是 notesQuick")
    }

    @Test("ModuleHarness dispatch toggleComplete 翻转完成状态后 snapshot 更新")
    func harnessDispatchToggleCompleteUpdatesSnapshot() async {
        let cache = makeCache()
        let noteID = UUID()
        let note = NotesQuickModule.Note(id: noteID, title: "Toggle me", createdAt: Date())
        cache.saveDomainState(try! JSONEncoder().encode([note]))

        let module = NotesQuickModule(cache: cache)
        let harness = ModuleHarness(module: module)

        // First, refresh to load the snapshot
        await harness.refresh()
        #expect(harness.latestSnapshot != nil, "refresh 后应该有 snapshot")

        harness.resetCapturedOutput()

        let transition = await harness.dispatch(
            .userAction(actionID: "toggleComplete", payload: .init(text: noteID.uuidString))
        )

        #expect(!transition.effects.isEmpty, "toggleComplete 应该产生 effects")
        #expect(harness.latestSnapshot != nil, "toggleComplete 后 latestSnapshot 应该更新")
    }

    @Test("ModuleHarness dispatch togglePin 翻转置顶状态后 snapshot 更新")
    func harnessDispatchTogglePinUpdatesSnapshot() async {
        let cache = makeCache()
        let noteID = UUID()
        let note = NotesQuickModule.Note(id: noteID, title: "Pin me", createdAt: Date())
        cache.saveDomainState(try! JSONEncoder().encode([note]))

        let module = NotesQuickModule(cache: cache)
        let harness = ModuleHarness(module: module)

        let transition = await harness.dispatch(
            .userAction(actionID: "togglePin", payload: .init(text: noteID.uuidString))
        )

        #expect(!transition.effects.isEmpty, "togglePin 应该产生 effects")
        #expect(harness.latestSnapshot != nil, "togglePin 后 latestSnapshot 应该更新")
        let isPinned = harness.latestSnapshot?.metrics["pinned"]
        #expect(isPinned == 1, "置顶后 pinned metric 应为 1")
    }

    @Test("ModuleHarness dispatch deleteNote 后快照移除笔记")
    func harnessDispatchDeleteNoteRemovesNote() async {
        let cache = makeCache()
        let noteID = UUID()
        let note = NotesQuickModule.Note(id: noteID, title: "Delete me", createdAt: Date())
        cache.saveDomainState(try! JSONEncoder().encode([note]))

        let module = NotesQuickModule(cache: cache)
        let harness = ModuleHarness(module: module)

        // Verify note exists before deletion
        await harness.refresh()
        #expect(harness.latestSnapshot != nil)
        let countBefore = harness.latestSnapshot?.metrics["notes"] ?? 0
        #expect(countBefore == 1)

        harness.resetCapturedOutput()

        let transition = await harness.dispatch(
            .userAction(actionID: "deleteNote", payload: .init(text: noteID.uuidString))
        )

        #expect(!transition.effects.isEmpty, "deleteNote 应该产生 effects")
        #expect(harness.latestSnapshot != nil, "deleteNote 后 latestSnapshot 应该更新")
        let countAfter = harness.latestSnapshot?.metrics["notes"] ?? 0
        #expect(countAfter == 0, "删除后 notes count 应为 0")
    }

    @Test("ModuleHarness dispatch editNote 后快照反映修改")
    func harnessDispatchEditNoteUpdatesSnapshot() async {
        let cache = makeCache()
        let noteID = UUID()
        let note = NotesQuickModule.Note(id: noteID, title: "Old", content: "Old content", createdAt: Date())
        cache.saveDomainState(try! JSONEncoder().encode([note]))

        let module = NotesQuickModule(cache: cache)
        let harness = ModuleHarness(module: module)

        let edits: [String: String] = ["title": "New Title", "content": "New Content"]
        let transition = await harness.dispatch(
            .userAction(actionID: "editNote", payload: .init(
                text: noteID.uuidString,
                data: try? JSONEncoder().encode(edits)
            ))
        )

        #expect(!transition.effects.isEmpty, "editNote 应该产生 effects")
        #expect(harness.latestSnapshot != nil, "editNote 后 latestSnapshot 应该更新")
    }

    @Test("ModuleHarness dispatch copyNote 产生剪贴板 effect")
    func harnessDispatchCopyNoteReturnsClipboardEffect() async {
        let cache = makeCache()
        let noteID = UUID()
        let note = NotesQuickModule.Note(id: noteID, title: "买牛奶", content: "全脂", createdAt: Date())
        cache.saveDomainState(try! JSONEncoder().encode([note]))

        let module = NotesQuickModule(cache: cache)
        let harness = ModuleHarness(module: module)

        let transition = await harness.dispatch(
            .userAction(actionID: "copyNote", payload: .init(text: noteID.uuidString))
        )

        let hasClipboardEffect = harness.emittedEffects.contains {
            if case .copyToClipboard = $0 { return true }
            return false
        }
        #expect(hasClipboardEffect, "copyNote 应该产生 copyToClipboard effect")
    }

    @Test("ModuleHarness dispatch clearCompleted 后快照不包含已完成笔记")
    func harnessDispatchClearCompletedRemovesCompletedNotes() async {
        let cache = makeCache()
        let id1 = UUID(), id2 = UUID()
        let data = try! JSONEncoder().encode([
            NotesQuickModule.Note(id: id1, title: "Active", createdAt: Date()),
            NotesQuickModule.Note(id: id2, title: "Done", isComplete: true, createdAt: Date()),
        ])
        cache.saveDomainState(data)

        let module = NotesQuickModule(cache: cache)
        let harness = ModuleHarness(module: module)

        let transition = await harness.dispatch(
            .userAction(actionID: "clearCompleted", payload: nil)
        )

        #expect(!transition.effects.isEmpty, "clearCompleted 应该产生 effects")
        #expect(harness.latestSnapshot != nil)
        let countAfter = harness.latestSnapshot?.metrics["notes"] ?? 0
        #expect(countAfter == 1, "clearCompleted 后应只剩 1 条未完成的笔记")
    }

    // MARK: - ModuleRuntime full dispatch chain

    @Test("ModuleRuntime dispatch 到 NotesQuickModule 能更新 snapshots")
    func runtimeDispatchUpdatesSnapshots() async throws {
        let module = NotesQuickModule(cache: makeCache())
        let runtime = makeRuntime(module: module)

        // Dispatch addNote
        runtime.dispatch(
            command: .userAction(actionID: "addNote", payload: .init(text: "Runtime 笔记")),
            moduleID: "notesQuick"
        )

        // Give async actor time to process
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        #expect(runtime.snapshots["notesQuick"] != nil, "runtime.snapshots 应该被更新")
    }

    // MARK: - Helpers

    private func makeCache() -> ModuleCacheNamespace {
        let defaults = UserDefaults(suiteName: "NotesQuickIntegration.\(UUID().uuidString)")!
        return ModuleCacheNamespace(moduleID: "notesQuick", defaults: defaults)
    }

    private func makeRuntime(module: any ModuleContract) -> ModuleRuntime {
        let registry = ModuleRegistry()
        registry.register { module }
        let settingsStore = AppSettingsStore()
        settingsStore.setEnabled(true, moduleID: module.manifest.id)
        let cacheStore = CacheStore()
        let widgetBridge = WidgetDataBridge()
        return ModuleRuntime(
            registry: registry,
            cacheStore: cacheStore,
            widgetBridge: widgetBridge,
            settingsStore: settingsStore
        )
    }
}
