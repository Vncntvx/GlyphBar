import XCTest
@testable import GlyphBar

@MainActor
final class TemplateModuleTests: XCTestCase {
    func testCounterActionsUpdateSnapshot() async throws {
        // Reset persisted counter state so the test starts from 0.
        UserDefaults.standard.removeObject(forKey: "counter.moduleState")
        let context = makeContext()
        let module = CounterModule()
        let action = module.manifest.actions.first { $0.id == "increment" }!

        let event = try await module.handle(action: action, context: context)

        guard case .didUpdateSnapshot(let snapshot) = event else {
            return XCTFail("Expected updated snapshot")
        }
        XCTAssertEqual(snapshot.metrics["count"], 1)
    }

    func testNetworkMockModuleRefreshSucceeds() async throws {
        let module = NetworkMockModule()
        // NOTE: NetworkMockModule.init() takes no arguments. Mock mode
        // is toggled via the panel UI binding (useMockMode). In real mode
        // the module uses NWPathMonitor for actual network status.

        let snapshot = try await module.refresh(context: makeContext())
        // Real refresh returns a snapshot based on current NWPath status.
        // Either "Connected", "No Connection", "Connecting…", or "Unknown".
        XCTAssertFalse(snapshot.title.isEmpty)
        XCTAssertFalse(snapshot.systemImage.isEmpty)
    }

    func testRegistrySeparatesBuiltInAndThirdPartyModules() throws {
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

        XCTAssertEqual(records["counter"]?.sourceKind, .builtIn)
        XCTAssertEqual(records["sampleThird"]?.sourceKind, .thirdParty)
    }

    func testRuntimeImportsValidThirdPartyPackage() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeModulePackage(in: root, id: "sampleImport")
        let runtime = makeRuntime(
            externalStore: ExternalModulePackageStore(
                modulesDirectory: root.appendingPathComponent("Installed", isDirectory: true)
            )
        )

        let moduleID = try runtime.importModule(from: source)

        XCTAssertEqual(moduleID, "sampleImport")
        XCTAssertEqual(runtime.record(for: "sampleImport")?.sourceKind, .thirdParty)
        XCTAssertTrue(runtime.settingsStore.isEnabled("sampleImport"))
    }

    func testRuntimeRejectsInvalidThirdPartyPackage() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let invalid = root.appendingPathComponent("Invalid.glyphbarmodule", isDirectory: true)
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
        let runtime = makeRuntime(
            externalStore: ExternalModulePackageStore(
                modulesDirectory: root.appendingPathComponent("Installed", isDirectory: true)
            )
        )

        XCTAssertThrowsError(try runtime.importModule(from: invalid))
    }

    func testRuntimeRemovesThirdPartyPackage() throws {
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

        XCTAssertNil(runtime.record(for: "sampleRemove"))
        XCTAssertFalse(runtime.settingsStore.isEnabled("sampleRemove"))
    }

    func testBuiltInModuleCannotBeRemoved() throws {
        let runtime = makeRuntime()

        XCTAssertThrowsError(try runtime.removeThirdPartyModule(moduleID: "counter"))
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
