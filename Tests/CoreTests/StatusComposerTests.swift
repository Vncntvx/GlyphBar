import Foundation
import Testing
@testable import GlyphBar

/// Tests for the PresentationArbiter which replaced StatusComposer.
/// The arbiter handles priority-based candidate selection with
/// hysteresis, TTL, and deduplication — all functions previously
/// in StatusComposer.
@MainActor
struct StatusComposerTests {
    @Test func criticalSignalOverridesPrimaryModule() {
        let fallback = PresentationDecision(
            title: "GlyphBar", systemImage: "sparkles",
            severity: .normal, tooltip: ""
        )
        let arbiter = PresentationArbiter(fallback: fallback)

        let candidates = [
            StatusCandidate(
                id: "clock.time", sourceModule: "clock",
                semanticRole: .primary, severity: .normal, priority: 50,
                text: "12:00", icon: "clock",
                createdAt: Date(), expiresAt: nil,
                interruptPolicy: .normal, trustLevel: .bundled
            ),
            StatusCandidate(
                id: "network.down", sourceModule: "networkMock",
                semanticRole: .alert, severity: .critical, priority: 100,
                text: "Network Down", icon: "wifi.slash",
                createdAt: Date(), expiresAt: nil,
                interruptPolicy: .preempt, trustLevel: .bundled
            )
        ]
        arbiter.submit(candidates, now: Date())
        #expect(arbiter.currentDecision.title == "Network Down")
        #expect(arbiter.currentDecision.severity == .critical)
    }

    @Test func warningCandidatesArePresented() {
        let fallback = PresentationDecision(
            title: "GlyphBar", systemImage: "sparkles",
            severity: .normal, tooltip: ""
        )
        let arbiter = PresentationArbiter(fallback: fallback)

        let candidates = [
            StatusCandidate(
                id: "a.warn", sourceModule: "a",
                semanticRole: .primary, severity: .warning, priority: 40,
                text: "A Warning", icon: "exclamationmark.triangle",
                createdAt: Date(), expiresAt: nil,
                interruptPolicy: .normal, trustLevel: .bundled
            ),
            StatusCandidate(
                id: "b.warn", sourceModule: "b",
                semanticRole: .primary, severity: .warning, priority: 40,
                text: "B Warning", icon: "exclamationmark.triangle",
                createdAt: Date(), expiresAt: nil,
                interruptPolicy: .normal, trustLevel: .bundled
            )
        ]
        arbiter.submit(candidates, now: Date())
        // The arbiter should pick one of the warning candidates (highest priority wins)
        #expect(arbiter.currentDecision.severity == .warning)
    }
}
