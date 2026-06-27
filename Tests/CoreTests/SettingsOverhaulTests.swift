import XCTest
@testable import GlyphBar

final class SettingsOverhaulTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "settings-overhaul-test-\(UUID().uuidString)")!
    }

    func testColorSchemePersists() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        store.colorScheme = "dark"
        XCTAssertEqual(defaults.string(forKey: "settings.colorScheme"), "dark")
        XCTAssertEqual(AppSettingsStore(defaults: defaults).colorScheme, "dark")
        XCTAssertEqual(AppSettingsStore(defaults: makeDefaults()).colorScheme, "system")
    }

    func testPinPanelPersists() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        store.pinPanel = true
        XCTAssertEqual(defaults.bool(forKey: "settings.pinPanel"), true)
        XCTAssertTrue(AppSettingsStore(defaults: defaults).pinPanel)
    }

    func testSetRefreshPolicyWritesAndPersists() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        store.setRefreshPolicy(.interval(seconds: 60), for: "clock")
        XCTAssertEqual(store.refreshPolicies["clock"], .interval(seconds: 60))
        XCTAssertEqual(AppSettingsStore(defaults: defaults).refreshPolicies["clock"], .interval(seconds: 60))
    }

    func testLoggerRingBufferAppendsAndCaps() {
        let logger = GlyphLogger()
        for index in 0..<600 { logger.info("message-\(index)") }
        let entries = logger.recentEntries()
        XCTAssertEqual(entries.count, 500)
        XCTAssertEqual(entries.last?.message, "message-599")
        XCTAssertEqual(entries.last?.category, "general")
        XCTAssertEqual(entries.last?.level, "info")
    }
}
