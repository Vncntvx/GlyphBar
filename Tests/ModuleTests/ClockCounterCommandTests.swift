import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct ClockCounterCommandTests {
    @Test func clockSetFormatCommandAssignsInsteadOfTogglingTwice() async {
        let suiteName = "ClockCommandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ModuleSettingsNamespace(moduleID: "clock", defaults: defaults)
        let harness = ModuleHarness(module: ClockModule(settings: settings))

        await harness.dispatch(.userAction(actionID: "setFormat24h", payload: .init(text: "false")))
        let firstState = decoded(ClockState.self, defaults: defaults, key: "module.clock.setting.moduleState")
        await harness.dispatch(.userAction(actionID: "setFormat24h", payload: .init(text: "false")))
        let secondState = decoded(ClockState.self, defaults: defaults, key: "module.clock.setting.moduleState")

        #expect(firstState?.uses24HourClock == false)
        #expect(secondState?.uses24HourClock == false)
    }

    @Test func clockWorldTimezoneCommandPersistsAllowedZonesOnly() async {
        let suiteName = "ClockCommandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ModuleSettingsNamespace(moduleID: "clock", defaults: defaults)
        let harness = ModuleHarness(module: ClockModule(settings: settings))
        let zones = ["Asia/Tokyo", "Invalid/Zone", "Europe/London"]
        let data = try? JSONEncoder().encode(zones)

        await harness.dispatch(.userAction(actionID: "setWorldTimezones", payload: .init(data: data)))

        let reloaded = ClockModule(settings: settings)
        let candidates = reloaded.statusCandidates().map(\.id)
        #expect(candidates.contains("clock.world.Asia/Tokyo"))
        #expect(candidates.contains("clock.world.Europe/London"))
        #expect(candidates.contains("clock.world.Invalid/Zone") == false)
    }

    @Test func counterCommandsUpdateSettingsAndSnapshotHeadlessly() async {
        let suiteName = "CounterCommandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ModuleSettingsNamespace(moduleID: "counter", defaults: defaults)
        let cache = ModuleCacheNamespace(moduleID: "counter", defaults: defaults)
        let harness = ModuleHarness(module: CounterModule(settings: settings, cache: cache))

        await harness.dispatch(.userAction(actionID: "setStepSize", payload: .init(text: "5")))
        await harness.dispatch(.userAction(actionID: "increment", payload: nil))

        #expect(harness.latestSnapshot?.metrics["count"] == 5)
        #expect(decoded(CounterState.self, defaults: defaults, key: "module.counter.setting.moduleState")?.stepSize == 5)

        let reloaded = CounterModule(settings: settings, cache: cache)
        let projection = reloaded.buildProjection()
        #expect(projection.summary?.title == "5")
    }

    private struct ClockState: Decodable {
        let uses24HourClock: Bool
        let showSeconds: Bool
        let worldTimezones: [String]
    }

    private struct CounterState: Decodable {
        let count: Int
        let stepSize: Int
        let minValue: Int?
        let maxValue: Int?
        let lastModified: Date?
    }

    private func decoded<T: Decodable>(_ type: T.Type, defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
