import Foundation
import Testing
@testable import GlyphBar

// MARK: - NotesQuickModule Manifest Contract Tests

/// 验证 NotesQuickModule 的 ModuleManifest.actions 声明与 handle 中
/// 实际处理的 user action 之间的一致性。
///
/// 模块在 handle 中处理的每个 user action ID 都必须出现在 manifest 的
/// actions 数组中，以便 DeepLinkRouter、Declarat iveModule 等外部
/// 路由层能够正确验证并分发命令。
@MainActor
struct NotesQuickModuleManifestContractTests {

    // MARK: - Action Coverage

    @Test("manifest.actions 覆盖 handle 中所有 user action")
    func manifestCoversAllHandledActions() {
        let module = NotesQuickModule()
        let manifest = module.manifest
        let declaredActions = Set(manifest.actions.map(\.id))

        let handledActions: Set<String> = [
            "addNote",
            "editNote",
            "toggleComplete",
            "togglePin",
            "deleteNote",
            "copyNote",
            "clearCompleted",
        ]

        for action in handledActions {
            #expect(
                declaredActions.contains(action),
                "Action '\(action)' is handled in NotesQuickModule.handle() but not declared in ModuleManifest.actions"
            )
        }
    }

    @Test("manifest.actions 中声明的 action ID 不为空且唯一")
    func manifestActionsAreValid() {
        let module = NotesQuickModule()
        let actions = module.manifest.actions

        // 每个 action 都有非空 ID
        for action in actions {
            #expect(!action.id.isEmpty, "ModuleAction.id must not be empty")
        }

        // action ID 唯一
        let ids = actions.map(\.id)
        #expect(ids.count == Set(ids).count, "ModuleManifest.actions 中 action ID 必须唯一")
    }

    // MARK: - Action ↔ Handler Round-Trip

    @Test("每个声明的 user action 都能通过 handle 产生非 empty 的 DomainTransition")
    func declaredActionsProduceNonEmptyTransition() async {
        let declaredUserActions = NotesQuickModule.staticManifest.actions
            .map(\.id)
            .filter { $0 != "clearCompleted" }

        for actionID in declaredUserActions {
            // 为每个 action 创建独立的 module + cache，避免副作用污染
            let cache = makeCache()
            let noteID = UUID()
            let noteData = try! JSONEncoder().encode([
                NotesQuickModule.Note(id: noteID, title: "Test", createdAt: Date()),
            ])
            cache.saveDomainState(noteData)
            let module = NotesQuickModule(cache: cache)

            let payload = actionPayloadFor(actionID: actionID, noteID: noteID)
            let result = await module.handle(
                command: .userAction(actionID: actionID, payload: payload),
                capabilities: makeCapabilities(cache: cache),
                bridge: MockModuleBridge()
            )
            #expect(
                !result.effects.isEmpty,
                "Declared action '\(actionID)' should produce effects when dispatched with valid payload"
            )
        }
    }

    // MARK: - Helpers

    private func makeCache() -> ModuleCacheNamespace {
        let defaults = UserDefaults(suiteName: "NotesQuickManifestTest.\(UUID().uuidString)")!
        return ModuleCacheNamespace(moduleID: "notesQuick", defaults: defaults)
    }

    private func makeCapabilities(cache: ModuleCacheNamespace) -> GrantedCapabilities {
        GrantedCapabilities(cache: cache, bridge: MockModuleBridge())
    }

    private func actionPayloadFor(actionID: String, noteID: UUID) -> Command.ActionPayload? {
        switch actionID {
        case "addNote":
            return .init(text: "Test note")
        case "editNote":
            let edits: [String: String] = ["title": "Updated", "content": "Updated content"]
            return .init(text: noteID.uuidString, data: try? JSONEncoder().encode(edits))
        case "toggleComplete", "togglePin", "deleteNote", "copyNote":
            return .init(text: noteID.uuidString)
        case "clearCompleted":
            return nil
        default:
            return nil
        }
    }
}
