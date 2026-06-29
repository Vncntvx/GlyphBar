import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct ArbiterTests {
    @Test func arbiterCriticalAlwaysBeatsPrimary() {
        let arbiter = PresentationArbiter()
        let now = Date()

        let primary = StatusCandidate(
            id: "primary", sourceModule: "clock", semanticRole: .primary,
            severity: .normal, priority: 50, text: "12:00", icon: "clock",
            createdAt: now, expiresAt: nil, interruptPolicy: .normal, trustLevel: .bundled
        )
        arbiter.submit([primary], now: now)
        #expect(arbiter.currentDecision.title == "12:00")

        let critical = StatusCandidate(
            id: "crit", sourceModule: "network", semanticRole: .alert,
            severity: .critical, priority: 10, text: "Offline", icon: "wifi.slash",
            createdAt: now, expiresAt: nil, interruptPolicy: .preempt, trustLevel: .bundled
        )
        arbiter.submit([primary, critical], now: now)
        #expect(arbiter.currentDecision.title == "Offline")
        #expect(arbiter.currentDecision.isCritical)
    }

    @Test func arbiterRespectsTTLExpiration() {
        let arbiter = PresentationArbiter()
        let now = Date()

        let expired = StatusCandidate(
            id: "expired", sourceModule: "m", semanticRole: .primary,
            severity: .critical, priority: 100, text: "Old", icon: "x",
            createdAt: now.addingTimeInterval(-10), expiresAt: now.addingTimeInterval(-1),
            interruptPolicy: .normal, trustLevel: .bundled
        )
        let fresh = StatusCandidate(
            id: "fresh", sourceModule: "m", semanticRole: .primary,
            severity: .normal, priority: 10, text: "New", icon: "y",
            createdAt: now, expiresAt: nil,
            interruptPolicy: .normal, trustLevel: .bundled
        )
        arbiter.submit([expired, fresh], now: now)
        #expect(arbiter.currentDecision.title == "New")
    }

    @Test func arbiterAppliesMinDisplayTimeHysteresis() {
        let arbiter = PresentationArbiter()
        let now = Date()

        let first = StatusCandidate(
            id: "first", sourceModule: "m", semanticRole: .primary,
            severity: .normal, priority: 50, text: "First", icon: "1",
            createdAt: now, expiresAt: nil, interruptPolicy: .normal, trustLevel: .bundled
        )
        arbiter.submit([first], now: now)
        #expect(arbiter.currentDecision.title == "First")

        // Submit a higher-priority candidate immediately — should NOT switch
        // because of the minimum display duration (3s default).
        let second = StatusCandidate(
            id: "second", sourceModule: "m", semanticRole: .primary,
            severity: .normal, priority: 90, text: "Second", icon: "2",
            createdAt: now, expiresAt: nil, interruptPolicy: .normal, trustLevel: .bundled
        )
        arbiter.submit([second], now: now.addingTimeInterval(1))
        #expect(arbiter.currentDecision.title == "First") // still showing first

        // After 5 seconds, the switch should happen.
        arbiter.submit([second], now: now.addingTimeInterval(5))
        #expect(arbiter.currentDecision.title == "Second")
    }

    @Test func arbiterDeduplicatesByCandidateKey() {
        let arbiter = PresentationArbiter()
        let now = Date()

        let dup1 = StatusCandidate(
            id: "same", sourceModule: "m", semanticRole: .primary,
            severity: .normal, priority: 50, text: "A", icon: "a",
            createdAt: now, expiresAt: nil, interruptPolicy: .normal, trustLevel: .bundled
        )
        let dup2 = StatusCandidate(
            id: "same", sourceModule: "m", semanticRole: .primary,
            severity: .normal, priority: 90, text: "B", icon: "b",
            createdAt: now, expiresAt: nil, interruptPolicy: .normal, trustLevel: .bundled
        )
        arbiter.submit([dup1, dup2], now: now)
        // First one wins due to deduplication.
        #expect(arbiter.currentDecision.title == "A")
    }

    @Test func arbiterUntrustedCannotStarveBundled() {
        let arbiter = PresentationArbiter()
        let now = Date()

        // Same priority — trust level breaks the tie.
        let bundled = StatusCandidate(
            id: "bundled", sourceModule: "clock", semanticRole: .primary,
            severity: .normal, priority: 50, text: "Bundled", icon: "c",
            createdAt: now, expiresAt: nil, interruptPolicy: .normal, trustLevel: .bundled
        )
        let untrusted = StatusCandidate(
            id: "untrusted", sourceModule: "third", semanticRole: .primary,
            severity: .normal, priority: 50, text: "Untrusted", icon: "u",
            createdAt: now, expiresAt: nil, interruptPolicy: .normal, trustLevel: .untrusted
        )
        arbiter.submit([bundled, untrusted], now: now)
        // Bundled wins due to higher trust level when priority is equal.
        #expect(arbiter.currentDecision.title == "Bundled")
    }
}
