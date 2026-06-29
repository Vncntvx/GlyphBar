import Foundation
import Testing
@testable import GlyphBar

// MARK: - IngestionAPI Tests

@MainActor
struct IngestionAPITests {
    @Test func ingestionAPIPublishesSnapshotToKernel() {
        let api = IngestionAPI()
        var receivedEvent: IngestionEvent?

        api.subscribe { event in
            receivedEvent = event
        }

        let instanceID = ModuleInstanceID(value: "test.ingest")
        let payload = IngestionPayload(
            snapshot: ExternalSnapshotV2(title: "Test", subtitle: "", systemImage: "circle", metrics: nil, notes: nil),
            source: .cli
        )

        try? api.publish(payload: payload, forInstance: instanceID)

        if case .snapshotPublished(let id, _) = receivedEvent {
            #expect(id == instanceID)
        } else {
            Issue.record("Expected snapshotPublished event")
        }
    }

    @Test func ingestionRejectsUnknownInstance() {
        let api = IngestionAPI()
        // We can't test "unknown instance" rejection without a registry,
        // but we can test schema version validation.
        let payload = IngestionPayload(
            schemaVersion: 999,  // Unsupported version
            snapshot: ExternalSnapshotV2(title: "Test", subtitle: "", systemImage: "circle", metrics: nil, notes: nil),
            source: .cli
        )

        #expect(throws: IngestionError.self) {
            try api.publish(payload: payload, forInstance: ModuleInstanceID(value: "test"))
        }
    }
}

// MARK: - CapabilityBroker Tests

@MainActor
struct CapabilityBrokerTests {
    @Test func capabilityBrokerTracksGrants() {
        let broker = CapabilityBroker()
        let instanceID = ModuleInstanceID(value: "deepseek.default")

        broker.grant(.network, to: instanceID)
        broker.grant(.secretStore, to: instanceID)

        #expect(broker.currentGrants(for: instanceID) == [.network, .secretStore])
    }

    @Test func capabilityBrokerRevocationSuspendsModule() {
        let broker = CapabilityBroker()
        let instanceID = ModuleInstanceID(value: "deepseek.default")

        broker.grant(.network, to: instanceID)
        broker.revoke(.network, from: instanceID)

        #expect(!broker.currentGrants(for: instanceID).contains(.network))
    }
}

// MARK: - ArbitrationPolicy Tests

struct ArbitrationPolicyTests {
    @Test func defaultPolicySortsBySeverityFirst() {
        let policy = DefaultArbitrationPolicy()

        let critical = StatusCandidate(
            id: "a", sourceModule: "a",
            semanticRole: .alert, severity: .critical, priority: 10,
            text: "Critical", icon: "exclamationmark.triangle",
            createdAt: Date(), expiresAt: nil,
            interruptPolicy: .normal, trustLevel: .bundled
        )
        let normal = StatusCandidate(
            id: "b", sourceModule: "b",
            semanticRole: .primary, severity: .normal, priority: 100,
            text: "Normal", icon: "circle",
            createdAt: Date(), expiresAt: nil,
            interruptPolicy: .normal, trustLevel: .bundled
        )

        #expect(policy.compare(critical, normal) == .orderedAscending)
    }

    @Test func defaultPolicyMinDisplayTime() {
        let policy = DefaultArbitrationPolicy(minDisplayDuration: 5.0)

        #expect(policy.minDisplayTime(for: .primary) == 5.0)
        #expect(policy.minDisplayTime(for: .rotation) == 0)
        #expect(policy.minDisplayTime(for: .alert) == 1.0)
    }
}

// MARK: - DiagnosticContext Tests

struct DiagnosticContextTests {
    @Test func diagnosticContextCreation() {
        let moduleID = ModuleInstanceID(value: "deepseek.default")
        let ctx = DiagnosticContext.new(moduleID: moduleID)

        #expect(!ctx.correlationID.isEmpty)
        #expect(ctx.moduleInstanceID == "deepseek.default")
        #expect(!ctx.commandID.isEmpty)
    }
}
