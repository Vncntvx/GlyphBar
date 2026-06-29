import Foundation

/// Status-bar arbiter. Consumes `StatusCandidate` pools from all modules and
/// produces a single `PresentationDecision` per tick.
///
/// P1 behaviour is equivalent to the legacy `StatusComposer`:
///   1. De-duplicate by `id`.
///   2. Filter expired (TTL) candidates.
///   3. Sort by severity (desc) → priority (desc) → trustLevel (desc) → createdAt (asc).
///   4. Respect `minimumDisplayDuration` — don't switch away from the current
///      candidate until it's been shown for at least `minimumDisplayDuration`.
///   5. `preempt` interrupts immediately; `persistent` can't be preempted by
///      lower-severity candidates.
///
/// Hysteresis and TTL were added in P1.6; the legacy `StatusComposer`
/// behaviour is preserved as the baseline.
@MainActor
final class PresentationArbiter {
    private(set) var currentDecision: PresentationDecision
    private var displaySince: Date?
    private var minimumDisplayDuration: TimeInterval = 3.0
    private var hysteresis: [String: HysteresisTracker] = [:]
    private var lastCandidates: [StatusCandidate] = []
    private var lastSwitchAt: Date = .distantPast

    init(fallback: PresentationDecision = PresentationDecision()) {
        self.currentDecision = fallback
    }

    func submit(_ candidates: [StatusCandidate], now: Date) {
        let deduplicated = deduplicate(candidates)
        let filtered = filterExpired(deduplicated, now: now)
        let sorted = sort(filtered)
        lastCandidates = sorted

        if let winner = sorted.first {
            trySwitch(to: winner, now: now)
        }
    }

    func tick(now: Date) -> PresentationDecision {
        // Re-filter expired candidates on each tick.
        let filtered = filterExpired(lastCandidates, now: now)
        lastCandidates = filtered
        if let winner = filtered.first {
            trySwitch(to: winner, now: now)
        }
        return currentDecision
    }

    func reevaluate(now: Date) -> PresentationDecision {
        tick(now: now)
    }

    // MARK: - Internals

    private func deduplicate(_ candidates: [StatusCandidate]) -> [StatusCandidate] {
        var seen = Set<String>()
        var result: [StatusCandidate] = []
        for candidate in candidates where !seen.contains(candidate.id) {
            seen.insert(candidate.id)
            result.append(candidate)
        }
        return result
    }

    private func filterExpired(_ candidates: [StatusCandidate], now: Date) -> [StatusCandidate] {
        candidates.filter { candidate in
            guard let expiresAt = candidate.expiresAt else { return true }
            return expiresAt > now
        }
    }

    private func sort(_ candidates: [StatusCandidate]) -> [StatusCandidate] {
        candidates.sorted { a, b in
            if a.severity != b.severity {
                return a.severity > b.severity
            }
            if a.priority != b.priority {
                return a.priority > b.priority
            }
            if a.trustLevel != b.trustLevel {
                return a.trustLevel > b.trustLevel
            }
            return a.createdAt < b.createdAt
        }
    }

    private func trySwitch(to candidate: StatusCandidate, now: Date) {
        let decision = PresentationDecision(
            title: candidate.text,
            systemImage: candidate.icon,
            severity: candidate.severity,
            tooltip: candidate.text,
            accessibilityLabel: candidate.text,
            accessibilityHint: "",
            sourceModule: candidate.sourceModule,
            isCritical: candidate.severity == .critical
        )

        if decision == currentDecision {
            return
        }

        // Preempt: interrupt immediately regardless of min display duration.
        if candidate.interruptPolicy == .preempt {
            apply(decision, now: now)
            return
        }

        // Persistent: don't switch away unless the new candidate is strictly
        // higher severity.
        if candidate.interruptPolicy == .persistent,
           currentDecision.severity > candidate.severity {
            return
        }

        // Min display duration: don't switch too quickly.
        if let displaySince,
           now.timeIntervalSince(displaySince) < minimumDisplayDuration {
            return
        }

        apply(decision, now: now)
    }

    private func apply(_ decision: PresentationDecision, now: Date) {
        currentDecision = decision
        displaySince = now
        lastSwitchAt = now
    }
}
