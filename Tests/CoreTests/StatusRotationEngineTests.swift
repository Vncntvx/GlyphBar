import Foundation
import Testing
@testable import GlyphBar

/// Tests for the PresentationArbiter which replaced StatusRotationEngine.
/// The arbiter handles candidate submission, TTL expiration, hysteresis,
/// and rotation tick — all functions previously split across
/// StatusRotationEngine + StatusComposer.
@MainActor
struct StatusRotationEngineTests {
    @Test func emptyArbiterReturnsFallback() {
        let fallback = PresentationDecision(
            title: "GlyphBar", systemImage: "sparkles",
            severity: .normal, tooltip: ""
        )
        let arbiter = PresentationArbiter(fallback: fallback)
        #expect(arbiter.currentDecision.title == "GlyphBar")
    }

    @Test func arbiterAcceptsCandidatesFromModules() {
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
            )
        ]
        arbiter.submit(candidates, now: Date())
        #expect(arbiter.currentDecision.title == "12:00")
    }

    @Test func arbiterTickAdvancesRotation() {
        let fallback = PresentationDecision(
            title: "GlyphBar", systemImage: "sparkles",
            severity: .normal, tooltip: ""
        )
        let arbiter = PresentationArbiter(fallback: fallback)

        let now = Date()
        let candidates = [
            StatusCandidate(
                id: "clock.time", sourceModule: "clock",
                semanticRole: .rotation, severity: .info, priority: 20,
                text: "12:00", icon: "clock",
                createdAt: now, expiresAt: nil,
                interruptPolicy: .normal, trustLevel: .bundled
            ),
            StatusCandidate(
                id: "counter.val", sourceModule: "counter",
                semanticRole: .rotation, severity: .info, priority: 20,
                text: "5", icon: "number",
                createdAt: now, expiresAt: nil,
                interruptPolicy: .normal, trustLevel: .bundled
            )
        ]
        arbiter.submit(candidates, now: now)

        // Advance time past minimumDisplayDuration so rotation can switch.
        let tick1Time = now.advanced(by: 4.0)
        let tick2Time = tick1Time.advanced(by: 4.0)
        let first = arbiter.tick(now: tick1Time)
        let second = arbiter.tick(now: tick2Time)
        // Rotation should advance through candidates
        #expect(first.title != second.title || candidates.count == 1)
    }

    @Test func arbiterTickReturnsFallbackWhenEmpty() {
        let fallback = PresentationDecision(
            title: "GlyphBar", systemImage: "sparkles",
            severity: .normal, tooltip: ""
        )
        let arbiter = PresentationArbiter(fallback: fallback)
        let decision = arbiter.tick(now: Date())
        #expect(decision.title == "GlyphBar")
    }
}
