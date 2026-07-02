import Foundation
import Testing
@testable import GlyphBar

// MARK: - Namespace Isolation

@MainActor
struct ModuleNamespaceIsolationTests {
    @Test func settingsNamespaceIsolatesTwoModules() {
        let defaults = UserDefaults(suiteName: "NamespaceIsolation.\(UUID().uuidString)")!
        let settingsA = ModuleSettingsNamespace(moduleID: "moduleA", defaults: defaults)
        let settingsB = ModuleSettingsNamespace(moduleID: "moduleB", defaults: defaults)

        settingsA["key"] = "valueA"
        settingsB["key"] = "valueB"

        #expect(settingsA["key"] == "valueA")
        #expect(settingsB["key"] == "valueB")
        #expect(settingsA["key"] != settingsB["key"])
    }

    @Test func cacheNamespaceIsolatesTwoModules() {
        let defaults = UserDefaults(suiteName: "CacheIsolation.\(UUID().uuidString)")!
        let cacheA = ModuleCacheNamespace(moduleID: "moduleA", defaults: defaults)
        let cacheB = ModuleCacheNamespace(moduleID: "moduleB", defaults: defaults)

        cacheA.saveDomainState(Data([0xAA]))
        cacheB.saveDomainState(Data([0xBB]))

        #expect(cacheA.loadDomainState() == Data([0xAA]))
        #expect(cacheB.loadDomainState() == Data([0xBB]))
    }

    @Test func settingsNamespaceCodableRoundTrip() {
        let defaults = UserDefaults(suiteName: "SettingsCodable.\(UUID().uuidString)")!
        let settings = ModuleSettingsNamespace(moduleID: "test", defaults: defaults)

        struct TestState: Codable, Equatable {
            let count: Int
            let label: String
        }

        let original = TestState(count: 42, label: "hello")
        settings.set(original, forKey: "state")

        let restored = settings.get(TestState.self, forKey: "state")
        #expect(restored == original)
    }

    @Test func settingsNamespaceRemovesNilValue() {
        let defaults = UserDefaults(suiteName: "SettingsNil.\(UUID().uuidString)")!
        let settings = ModuleSettingsNamespace(moduleID: "test", defaults: defaults)

        settings["key"] = "value"
        #expect(settings["key"] != nil)

        settings["key"] = nil
        #expect(settings["key"] == nil)
    }
}

// MARK: - SnapshotEnvelope Contract

struct SnapshotEnvelopeContractTests {
    @Test func snapshotEnvelopeCarriesAllFields() {
        let projections = ProjectionSet()
        let envelope = SnapshotEnvelope(
            id: "test.envelope",
            schemaVersion: 1,
            capturedAt: Date(),
            validUntil: Date().addingTimeInterval(300),
            freshness: .fresh,
            health: .healthy,
            projections: projections
        )

        #expect(envelope.id == "test.envelope")
        #expect(envelope.schemaVersion == 1)
        #expect(envelope.freshness == .fresh)
        #expect(envelope.health == .healthy)
        #expect(envelope.validUntil != nil)
    }

    @Test func snapshotEnvelopeDefaultsAreSensible() {
        let projections = ProjectionSet()
        let envelope = SnapshotEnvelope(id: "defaults", projections: projections)

        #expect(envelope.schemaVersion == 1)
        #expect(envelope.health == .healthy)
        #expect(envelope.freshness == .fresh)
        #expect(envelope.validUntil == nil)
    }

    @Test func snapshotEnvelopeWithStaleFreshness() {
        let projections = ProjectionSet()
        let staleDate = Date().addingTimeInterval(-60)
        let envelope = SnapshotEnvelope(
            id: "stale.test",
            freshness: .stale(staleDate),
            health: .degraded(reason: .networkError("timeout")),
            projections: projections
        )

        #expect(envelope.freshness == .stale(staleDate))
        #expect(envelope.health.isUnhealthy == true)
    }

    @Test func snapshotEnvelopeWithUnavailableFreshness() {
        let projections = ProjectionSet()
        let envelope = SnapshotEnvelope(
            id: "unavail.test",
            freshness: .unavailable("module crashed"),
            health: .unavailable(reason: .unknown("crash")),
            projections: projections
        )

        #expect(envelope.freshness.isAvailable == false)
        #expect(envelope.health.isTerminal == true)
    }
}

// MARK: - PresentationTickable Contract

@MainActor
struct PresentationTickableContractTests {
    @Test func clockPresentationTickReturnsUpdatedCandidates() {
        let module = ClockModule()
        var projection = module.buildProjection()
        projection.statusCandidates = module.statusCandidates()

        let ticked = module.presentationTick(trigger: .timerTick, projection: projection)

        #expect(ticked.statusCandidates.isEmpty == false)
        let primary = ticked.statusCandidates.first { $0.id == "clock.primary" }
        #expect(primary != nil, "primary candidate must survive tick")
    }

    @Test func clockPresentationTickIsIdempotent() {
        let module = ClockModule()
        var projection = module.buildProjection()
        projection.statusCandidates = module.statusCandidates()

        let ticked1 = module.presentationTick(trigger: .timerTick, projection: projection)
        let ticked2 = module.presentationTick(trigger: .timerTick, projection: ticked1)

        #expect(ticked1.statusCandidates.count == ticked2.statusCandidates.count)
    }

    @Test func clockPresentationTickPreservesRotationCandidates() {
        let defaults = UserDefaults(suiteName: "TickRotation.\(UUID().uuidString)")!
        let settings = ModuleSettingsNamespace(moduleID: "clock", defaults: defaults)
        settings.set(["Asia/Tokyo", "Europe/London"], forKey: "moduleState")
        let module = ClockModule(settings: settings)

        var projection = module.buildProjection()
        projection.statusCandidates = module.statusCandidates()
        let ticked = module.presentationTick(trigger: .timerTick, projection: projection)

        let rotationBefore = projection.statusCandidates.filter { $0.semanticRole == .rotation }
        let rotationAfter = ticked.statusCandidates.filter { $0.semanticRole == .rotation }
        #expect(rotationBefore.count == rotationAfter.count,
                "tick must not remove rotation candidates")
    }
}
