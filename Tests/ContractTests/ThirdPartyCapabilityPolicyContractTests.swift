import Foundation
import Testing
@testable import GlyphBar

// MARK: - CapabilityBroker Contract

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

// MARK: - ArbitrationPolicy Contract

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
        #expect(policy.minDisplayTime(for: .informational) == 5.0)
    }

    @Test func defaultPolicyCooldownBySeverity() {
        let policy = DefaultArbitrationPolicy()
        #expect(policy.cooldown(for: .critical) >= policy.cooldown(for: .normal))
    }
}
