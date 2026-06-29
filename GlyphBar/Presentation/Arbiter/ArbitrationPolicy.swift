import Foundation

/// Injectable arbitration policy that controls how the arbiter selects
/// and switches between candidates. Default implementation matches
/// the P1 behavior; custom policies can be injected for different
/// trust models or display requirements.
protocol ArbitrationPolicy: Sendable {
    /// Compare two candidates. Returns .orderedAscending if `a` should
    /// be preferred over `b`.
    func compare(_ a: StatusCandidate, _ b: StatusCandidate) -> ComparisonResult

    /// Whether a new candidate should preempt the current decision.
    func shouldPreempt(current: PresentationDecision, candidate: StatusCandidate, now: Date) -> Bool

    /// Minimum display time before switching away from a candidate with
    /// the given semantic role.
    func minDisplayTime(for role: StatusCandidate.SemanticRole) -> TimeInterval

    /// Cooldown period after displaying a candidate with the given severity.
    func cooldown(for severity: Severity) -> TimeInterval
}

/// Default arbitration policy matching P1 behavior.
struct DefaultArbitrationPolicy: ArbitrationPolicy {
    let minDisplayDuration: TimeInterval
    let defaultCooldown: TimeInterval

    init(minDisplayDuration: TimeInterval = 3.0, defaultCooldown: TimeInterval = 0) {
        self.minDisplayDuration = minDisplayDuration
        self.defaultCooldown = defaultCooldown
    }

    func compare(_ a: StatusCandidate, _ b: StatusCandidate) -> ComparisonResult {
        // Severity > priority > trustLevel > createdAt
        if a.severity != b.severity {
            return a.severity > b.severity ? .orderedAscending : .orderedDescending
        }
        if a.priority != b.priority {
            return a.priority > b.priority ? .orderedAscending : .orderedDescending
        }
        if a.trustLevel != b.trustLevel {
            return a.trustLevel > b.trustLevel ? .orderedAscending : .orderedDescending
        }
        if a.createdAt != b.createdAt {
            return a.createdAt < b.createdAt ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }

    func shouldPreempt(current: PresentationDecision, candidate: StatusCandidate, now: Date) -> Bool {
        switch candidate.interruptPolicy {
        case .preempt: return true
        case .persistent: return candidate.severity > current.severity
        case .normal: return false
        }
    }

    func minDisplayTime(for role: StatusCandidate.SemanticRole) -> TimeInterval {
        switch role {
        case .primary: return minDisplayDuration
        case .alert: return 1.0  // Alerts can switch faster
        case .rotation: return 0  // Rotation switches freely
        case .informational: return minDisplayDuration
        }
    }

    func cooldown(for severity: Severity) -> TimeInterval {
        defaultCooldown
    }
}
