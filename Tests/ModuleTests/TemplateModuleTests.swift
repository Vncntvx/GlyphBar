import XCTest
@testable import GlyphBar

@MainActor
final class TemplateModuleTests: XCTestCase {
    func testCounterActionsUpdateSnapshot() async throws {
        let context = makeContext()
        let module = CounterModule()
        let action = module.manifest.actions.first { $0.id == "increment" }!

        let event = try await module.handle(action: action, context: context)

        guard case .didUpdateSnapshot(let snapshot) = event else {
            return XCTFail("Expected updated snapshot")
        }
        XCTAssertEqual(snapshot.metrics["count"], 1)
    }

    func testNetworkFailureCanBeForced() async {
        let module = NetworkMockModule(forcedResults: [false])

        do {
            _ = try await module.refresh(context: makeContext())
            XCTFail("Expected refresh failure")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
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
}
