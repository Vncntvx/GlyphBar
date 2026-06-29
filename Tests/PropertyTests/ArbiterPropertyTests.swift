import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct ArbiterPropertyTests {
    @Test func arbiterDeterministicAcrossDictOrderings() {
        let now = Date()
        let candidates = (0..<20).map { i in
            StatusCandidate(
                id: "c\(i)", sourceModule: "m\(i)", semanticRole: .primary,
                severity: .normal, priority: i, text: "T\(i)", icon: "i\(i)",
                createdAt: now, expiresAt: nil, interruptPolicy: .normal, trustLevel: .bundled
            )
        }

        // Submit in forward order.
        let arbiter1 = PresentationArbiter()
        arbiter1.submit(candidates, now: now)

        // Submit in reversed order.
        let arbiter2 = PresentationArbiter()
        arbiter2.submit(candidates.reversed(), now: now)

        // Both should pick the same winner (highest priority = T19).
        #expect(arbiter1.currentDecision.title == arbiter2.currentDecision.title)
        #expect(arbiter1.currentDecision.title == "T19")
    }
}
