import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct TemplateModuleTests {
    @Test func counterActionsUpdateSnapshot() async throws {
        UserDefaults.standard.removeObject(forKey: "counter.moduleState")
        let context = makeContext()
        let module = CounterModule()
        let action = try #require(module.manifest.actions.first { $0.id == "increment" })

        let event = try await module.handle(action: action, context: context)

        guard case .didUpdateSnapshot(let snapshot) = event else {
            Issue.record("Expected updated snapshot")
            return
        }
        #expect(snapshot.metrics["count"] == 1)
    }

    @Test func networkMockModuleRefreshSucceeds() async throws {
        let module = NetworkMockModule()
        let snapshot = try await module.refresh(context: makeContext())
        #expect(snapshot.title.isEmpty == false)
        #expect(snapshot.systemImage.isEmpty == false)
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

    private func makeContext() -> ModuleContext {
        let defaults = UserDefaults(suiteName: "TemplateModuleTests.\(UUID().uuidString)")!
        let logger = GlyphLogger()
        let cache = CacheStore(defaults: defaults)
        return ModuleContext(
            logger: logger,
            cacheStore: cache,
            secureStore: SecureStore(defaults: defaults),
            permissionCenter: PermissionCenter(defaults: defaults),
            settingsStore: AppSettingsStore(defaults: defaults),
            platformActions: PlatformActions(),
            widgetBridge: WidgetDataBridge(defaults: defaults)
        )
    }

    private func makeRuntime() -> ModuleRuntime {
        makeRuntime(externalStore: ExternalModulePackageStore(modulesDirectory: temporaryDirectory()))
    }

    private func makeRuntime(externalStore: ExternalModulePackageStore) -> ModuleRuntime {
        let context = makeContext()
        let registry = ModuleRegistry(externalStore: externalStore)
        registry.register { CounterModule() }
        return ModuleRuntime(registry: registry, context: context, settingsStore: context.settingsStore)
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
