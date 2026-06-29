import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct TemplateModuleTests {
    @Test func counterActionsUpdateSnapshot() async throws {
        UserDefaults.standard.removeObject(forKey: "counter.moduleState")
        let bridge = KernelBridge { _ in }
        let capabilities = GrantedCapabilities(bridge: bridge)
        let module = CounterModule()

        let transition = await module.handle(
            command: .userAction(actionID: "increment", payload: nil),
            capabilities: capabilities,
            bridge: bridge
        )

        #expect(transition.effects.contains { if case .publishSnapshot = $0 { true } else { false } })
    }

    @Test func networkMockModuleRefreshSucceeds() async throws {
        let bridge = KernelBridge { _ in }
        let capabilities = GrantedCapabilities(bridge: bridge)
        let module = NetworkMockModule()

        let transition = await module.handle(
            command: .refresh(reason: .manual),
            capabilities: capabilities,
            bridge: bridge
        )

        #expect(transition.effects.contains { if case .publishSnapshot = $0 { true } else { false } })
    }

    @Test func registrySeparatesBuiltInAndThirdPartyModules() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeModulePackage(in: root, id: "sampleThird")
        let store = ExternalModulePackageStore(
            modulesDirectory: root.appendingPathComponent("Installed", isDirectory: true)
        )
        _ = try store.importPackage(from: source)

        let registry = ModuleRegistry(externalStore: store)
        registry.register { CounterModule() }

        let records = registry.makeRecords()

        #expect(records["counter"]?.sourceKind == .builtIn)
        #expect(records["sampleThird"]?.sourceKind == .thirdParty)
    }

    @Test func runtimeImportsValidThirdPartyPackage() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeModulePackage(in: root, id: "sampleImport")
        let runtime = makeRuntime(
            externalStore: ExternalModulePackageStore(
                modulesDirectory: root.appendingPathComponent("Installed", isDirectory: true)
            )
        )

        let moduleID = try runtime.importModule(from: source)

        #expect(moduleID == "sampleImport")
        #expect(runtime.record(for: "sampleImport")?.sourceKind == .thirdParty)
        #expect(runtime.settingsStore.isEnabled("sampleImport") == true)
    }

    @Test func runtimeRejectsInvalidThirdPartyPackage() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let invalid = root.appendingPathComponent("Invalid.glyphbarmodule", isDirectory: true)
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
        let runtime = makeRuntime(
            externalStore: ExternalModulePackageStore(
                modulesDirectory: root.appendingPathComponent("Installed", isDirectory: true)
            )
        )

        #expect(throws: Error.self) {
            try runtime.importModule(from: invalid)
        }
    }

    @Test func runtimeRemovesThirdPartyPackage() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeModulePackage(in: root, id: "sampleRemove")
        let runtime = makeRuntime(
            externalStore: ExternalModulePackageStore(
                modulesDirectory: root.appendingPathComponent("Installed", isDirectory: true)
            )
        )
        _ = try runtime.importModule(from: source)

        try runtime.removeThirdPartyModule(moduleID: "sampleRemove")

        #expect(runtime.record(for: "sampleRemove") == nil)
        #expect(runtime.settingsStore.isEnabled("sampleRemove") == false)
    }

    @Test func builtInModuleCannotBeRemoved() throws {
        let runtime = makeRuntime()

        #expect(throws: Error.self) {
            try runtime.removeThirdPartyModule(moduleID: "counter")
        }
    }

    // MARK: - Helpers

    private func makeRuntime() -> ModuleRuntime {
        makeRuntime(externalStore: ExternalModulePackageStore(modulesDirectory: temporaryDirectory()))
    }

    private func makeRuntime(externalStore: ExternalModulePackageStore) -> ModuleRuntime {
        let defaults = UserDefaults(suiteName: "TemplateModuleTests.\(UUID().uuidString)")!
        let cache = CacheStore(defaults: defaults)
        let widgetBridge = WidgetDataBridge(defaults: defaults)
        let settingsStore = AppSettingsStore(defaults: defaults)
        let logger = GlyphLogger()
        let registry = ModuleRegistry(externalStore: externalStore)
        registry.register { CounterModule() }
        return ModuleRuntime(
            registry: registry,
            cacheStore: cache,
            widgetBridge: widgetBridge,
            settingsStore: settingsStore,
            logger: logger
        )
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("GlyphBarTests.\(UUID().uuidString)", isDirectory: true)
    }

    private func makeModulePackage(in root: URL, id: String) throws -> URL {
        let package = root.appendingPathComponent("\(id).glyphbarmodule", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)

        let manifest = """
        {
          "schemaVersion": 1,
          "id": "\(id)",
          "displayName": "Sample Third",
          "subtitle": "External sample module",
          "systemImage": "sparkles",
          "version": "1.0.0",
          "author": "GlyphBar Tests",
          "minimumGlyphBarVersion": "1.0",
          "capabilities": ["statusItem", "panel", "actions", "widgets", "deepLinks"],
          "permissions": ["pasteboard"],
          "refreshPolicy": { "type": "manual" },
          "actions": [
            {
              "id": "copy",
              "title": "Copy",
              "systemImage": "doc.on.doc",
              "kind": "copy",
              "value": "sample"
            }
          ],
          "widgets": [
            {
              "id": "\(id).widget",
              "title": "Sample",
              "subtitle": "Cached snapshot",
              "systemImage": "sparkles",
              "supportedFamilies": ["small", "medium"]
            }
          ],
          "panel": {
            "metricOrder": ["value"],
            "noteTitle": "Notes",
            "metadataKeys": ["source"]
          }
        }
        """

        let snapshot = """
        {
          "title": "42",
          "subtitle": "Ready",
          "metrics": { "value": 42 },
          "notes": ["Imported module snapshot"],
          "metadata": { "source": "test" }
        }
        """

        try manifest.write(to: package.appendingPathComponent("glyphbar-module.json"), atomically: true, encoding: .utf8)
        try snapshot.write(to: package.appendingPathComponent("snapshot.json"), atomically: true, encoding: .utf8)
        return package
    }
}
