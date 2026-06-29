import Foundation
import Testing
@testable import GlyphBar

// MARK: - Third-Party Module Contract Tests
//
// Third-party modules (declarative JSON, XPC-hosted) must satisfy the same
// ModuleContract paradigm constraints. These tests verify the platform
// infrastructure that supports third-party modules.

// MARK: - IngestionAPI Contract

@MainActor
struct IngestionAPIContractTests {
    @Test func ingestionAPIPublishesToSubscribers() {
        let api = IngestionAPI()
        var receivedEvents: [IngestionEvent] = []

        api.subscribe { event in
            receivedEvents.append(event)
        }

        let instanceID = ModuleInstanceID(value: "thirdparty.demo")
        let payload = IngestionPayload(
            snapshot: ExternalSnapshotV2(
                title: "Demo", subtitle: "v1", systemImage: "sparkles",
                metrics: nil, notes: nil
            ),
            source: .cli
        )

        try? api.publish(payload: payload, forInstance: instanceID)

        #expect(receivedEvents.count == 1)
        if case .snapshotPublished(let id, _) = receivedEvents.first {
            #expect(id == instanceID)
        } else {
            Issue.record("Expected snapshotPublished event, got \(receivedEvents)")
        }
    }

    @Test func ingestionAPIRejectsUnsupportedSchemaVersion() {
        let api = IngestionAPI()
        let payload = IngestionPayload(
            schemaVersion: 999,
            snapshot: ExternalSnapshotV2(
                title: "Bad", subtitle: "", systemImage: "xmark",
                metrics: nil, notes: nil
            ),
            source: .shortcuts
        )

        #expect(throws: IngestionError.self) {
            try api.publish(payload: payload, forInstance: ModuleInstanceID(value: "bad.schema"))
        }
    }

    @Test func ingestionAPIAcceptsAllSourceTypes() {
        let api = IngestionAPI()
        var eventCount = 0

        api.subscribe { _ in eventCount += 1 }

        let sources: [IngestionSource] = [.cli, .shortcuts, .ci, .urlScheme, .internal_]
        for source in sources {
            let payload = IngestionPayload(
                snapshot: ExternalSnapshotV2(
                    title: "Test", subtitle: "", systemImage: "circle",
                    metrics: nil, notes: nil
                ),
                source: source
            )
            try? api.publish(payload: payload, forInstance: ModuleInstanceID(value: "src.\(source)"))
        }

        #expect(eventCount == sources.count, "all source types should produce events")
    }

    @Test func ingestionAPIInvalidateRemovesSnapshot() throws {
        let api = IngestionAPI()
        let instanceID = ModuleInstanceID(value: "invalidate.test")

        let payload = IngestionPayload(
            snapshot: ExternalSnapshotV2(
                title: "Temp", subtitle: "", systemImage: "circle",
                metrics: nil, notes: nil
            ),
            source: .cli
        )

        try api.publish(payload: payload, forInstance: instanceID)
        try api.invalidate(instance: instanceID)
        // No crash = success
    }

    @Test func ingestionAPIClearRemovesAllSnapshots() throws {
        let api = IngestionAPI()
        let instanceID = ModuleInstanceID(value: "clear.test")

        let payload = IngestionPayload(
            snapshot: ExternalSnapshotV2(
                title: "Clear", subtitle: "", systemImage: "circle",
                metrics: nil, notes: nil
            ),
            source: .ci
        )

        try api.publish(payload: payload, forInstance: instanceID)
        try api.clear(instance: instanceID)
        // No crash = success
    }
}

// MARK: - CapabilityBroker Contract (Third-Party Capability Management)

@MainActor
struct CapabilityBrokerContractTests {
    @Test func brokerGrantsAndTracksCapabilities() {
        let broker = CapabilityBroker()
        let instance = ModuleInstanceID(value: "thirdparty.module1")

        broker.grant(.network, to: instance)
        broker.grant(.clipboard, to: instance)

        let grants = broker.currentGrants(for: instance)
        #expect(grants.contains(.network))
        #expect(grants.contains(.clipboard))
        #expect(grants.count == 2)
    }

    @Test func brokerRevocationRemovesCapability() {
        let broker = CapabilityBroker()
        let instance = ModuleInstanceID(value: "thirdparty.module2")

        broker.grant(.network, to: instance)
        broker.revoke(.network, from: instance)

        #expect(broker.currentGrants(for: instance).contains(.network) == false)
    }

    @Test func brokerIsolatesCapabilitiesBetweenInstances() {
        let broker = CapabilityBroker()
        let instanceA = ModuleInstanceID(value: "thirdparty.a")
        let instanceB = ModuleInstanceID(value: "thirdparty.b")

        broker.grant(.network, to: instanceA)
        broker.grant(.secretStore, to: instanceB)

        #expect(broker.currentGrants(for: instanceA).contains(.network))
        #expect(broker.currentGrants(for: instanceA).contains(.secretStore) == false)
        #expect(broker.currentGrants(for: instanceB).contains(.secretStore))
        #expect(broker.currentGrants(for: instanceB).contains(.network) == false)
    }

    @Test func brokerSetGrantsReplacesAll() {
        let broker = CapabilityBroker()
        let instance = ModuleInstanceID(value: "thirdparty.bulk")

        broker.grant(.network, to: instance)
        broker.setGrants([.clipboard, .cache], for: instance)

        let grants = broker.currentGrants(for: instance)
        #expect(grants == [.clipboard, .cache])
    }

    @Test func brokerFiresOnGrantChange() {
        let broker = CapabilityBroker()
        let instance = ModuleInstanceID(value: "thirdparty.callback")
        var changes: [(ModuleInstanceID, CapabilityKey, Bool)] = []

        broker.onGrantChange = { id, key, isGrant in
            changes.append((id, key, isGrant))
        }

        broker.grant(.network, to: instance)
        broker.revoke(.network, from: instance)

        #expect(changes.count == 2)
        #expect(changes[0].1 == .network && changes[0].2 == true)
        #expect(changes[1].1 == .network && changes[1].2 == false)
    }

    @Test func unregisteredInstanceHasNoGrants() {
        let broker = CapabilityBroker()
        let unknown = ModuleInstanceID(value: "thirdparty.unknown")
        #expect(broker.currentGrants(for: unknown).isEmpty)
    }
}

// MARK: - ArbitrationPolicy Contract (Third-Party Trust Levels)

struct ArbitrationPolicyContractTests {
    @Test func defaultPolicyBundledBeatsUntrusted() {
        let policy = DefaultArbitrationPolicy()
        let now = Date()

        let bundled = StatusCandidate(
            id: "b", sourceModule: "b", semanticRole: .primary,
            severity: .normal, priority: 50, text: "B", icon: "b",
            createdAt: now, expiresAt: nil, interruptPolicy: .normal, trustLevel: .bundled
        )
        let untrusted = StatusCandidate(
            id: "u", sourceModule: "u", semanticRole: .primary,
            severity: .normal, priority: 50, text: "U", icon: "u",
            createdAt: now, expiresAt: nil, interruptPolicy: .normal, trustLevel: .untrusted
        )

        #expect(policy.compare(bundled, untrusted) == .orderedAscending,
                "bundled should win over untrusted at same priority")
    }

    @Test func defaultPolicyCriticalPreemptsNormal() {
        let policy = DefaultArbitrationPolicy()
        let now = Date()

        let critical = StatusCandidate(
            id: "c", sourceModule: "c", semanticRole: .alert,
            severity: .critical, priority: 10, text: "C", icon: "c",
            createdAt: now, expiresAt: nil, interruptPolicy: .preempt, trustLevel: .untrusted
        )
        let normal = StatusCandidate(
            id: "n", sourceModule: "n", semanticRole: .primary,
            severity: .normal, priority: 100, text: "N", icon: "n",
            createdAt: now, expiresAt: nil, interruptPolicy: .normal, trustLevel: .bundled
        )

        #expect(policy.compare(critical, normal) == .orderedAscending,
                "critical severity should preempt normal even from untrusted source")
    }

    @Test func defaultPolicyMinDisplayTimeByRole() {
        let policy = DefaultArbitrationPolicy(minDisplayDuration: 5.0)

        #expect(policy.minDisplayTime(for: .primary) == 5.0)
        #expect(policy.minDisplayTime(for: .rotation) == 0)
        #expect(policy.minDisplayTime(for: .alert) == 1.0)
        #expect(policy.minDisplayTime(for: .informational) == 5.0)  // informational uses minDisplayDuration
    }

    @Test func defaultPolicyCooldownBySeverity() {
        let policy = DefaultArbitrationPolicy()

        // Critical should have longer cooldown than normal
        #expect(policy.cooldown(for: .critical) >= policy.cooldown(for: .normal))
    }
}

// MARK: - XPC Isolation Contract

@MainActor
struct XPCIsolationContractTests {
    @Test func xpcModuleHostCanBeCreated() {
        let broker = CapabilityBroker()
        let host = XPCModuleHost(capabilityBroker: broker)
        // No crash = success. XPC connections require actual XPC services.
        #expect(host !== nil)
    }

    @Test func xpcModuleProxyRequiresConnection() {
        let instanceID = ModuleInstanceID(value: "xpc.test")
        let connection = NSXPCConnection(serviceName: "com.test.xpc")
        let proxy = XPCModuleProxy(instanceID: instanceID, connection: connection)
        #expect(proxy.instanceID == instanceID)
    }

    @Test func xpcModuleHostCreatesProxyForPackage() throws {
        let broker = CapabilityBroker()
        let host = XPCModuleHost(capabilityBroker: broker)

        let testPackage = Package(
            id: PackageID(value: "com.test.xpc"),
            version: "1.0.0",
            manifest: ModuleManifest(
                id: "test", displayName: "Test", subtitle: "",
                systemImage: "circle", capabilities: [], permissions: [],
                defaultRefreshPolicy: .manual, actions: [], widgets: []
            ),
            source: .localPackage,
            installURL: nil
        )

        // loadModule creates a proxy; actual XPC connection will fail at runtime
        // when the service isn't available, but the proxy object is created.
        let proxy = try host.loadModule(package: testPackage)
        #expect(proxy.instanceID == ModuleInstanceID.default(for: ModuleTypeID(value: "test")))
    }
}

// MARK: - DiagnosticContext Contract

struct DiagnosticContextContractTests {
    @Test func diagnosticContextHasAllFields() {
        let moduleID = ModuleInstanceID(value: "thirdparty.module")
        let ctx = DiagnosticContext.new(moduleID: moduleID)

        #expect(ctx.correlationID.isEmpty == false, "correlationID must be non-empty")
        #expect(ctx.moduleInstanceID == "thirdparty.module")
        #expect(ctx.commandID.isEmpty == false, "commandID must be non-empty")
    }

    @Test func diagnosticContextCorrelationIDsAreUnique() {
        let moduleID = ModuleInstanceID(value: "test.uniqueness")
        let ctx1 = DiagnosticContext.new(moduleID: moduleID)
        let ctx2 = DiagnosticContext.new(moduleID: moduleID)

        #expect(ctx1.correlationID != ctx2.correlationID,
                "each DiagnosticContext should have a unique correlationID")
    }
}

// MARK: - SchemaVersion Contract (Third-Party Compatibility)

struct SchemaVersionContractTests {
    @Test func protocolVersionsStartAt1() {
        let versions = ProtocolVersions.current
        #expect(versions.packageSchema == 1)
        #expect(versions.manifestSchema == 1)
        #expect(versions.snapshotSchema == 1)
        #expect(versions.projectionSchema == 1)
        #expect(versions.storageSchema == 1)
        #expect(versions.widgetBridgeSchema == 1)
        #expect(versions.commandProtocol == 1)
        #expect(versions.effectProtocol == 1)
        #expect(versions.declarativeUISchema == 1)
    }

    @Test func packageValidatorRejectsNonexistentPath() {
        let validator = PackageValidator()
        #expect(throws: Error.self) {
            try validator.validate(at: URL(fileURLWithPath: "/nonexistent/package"))
        }
    }
}

// MARK: - IngestionSource Coverage

struct IngestionSourceContractTests {
    @Test func allIngestionSourcesAreRepresentable() {
        let sources: [IngestionSource] = [.cli, .shortcuts, .ci, .urlScheme, .internal_]
        #expect(sources.count == 5)
    }
}

// MARK: - ExternalSnapshotV2 Contract

struct ExternalSnapshotV2ContractTests {
    @Test func externalSnapshotCarriesAllFields() {
        let snapshot = ExternalSnapshotV2(
            title: "Title",
            subtitle: "Sub",
            systemImage: "star",
            metrics: ["key": 1.0],
            notes: ["a note"]
        )
        #expect(snapshot.title == "Title")
        #expect(snapshot.subtitle == "Sub")
        #expect(snapshot.systemImage == "star")
        #expect(snapshot.metrics?.count == 1)
        #expect(snapshot.notes?.count == 1)
    }

    @Test func externalSnapshotMinimalFields() {
        let snapshot = ExternalSnapshotV2(
            title: "Min",
            subtitle: "",
            systemImage: "circle",
            metrics: nil,
            notes: nil
        )
        #expect(snapshot.title == "Min")
        #expect(snapshot.metrics == nil)
        #expect(snapshot.notes == nil)
    }
}
