import Foundation

/// Metadata for a registered refresh job.
struct RefreshJob: Sendable {
    let moduleID: ModuleID
    let policy: RefreshPolicy
    let priority: RefreshScheduler.Priority
    var lastFireAt: Date?
    var consecutiveFailures: Int = 0
}

/// Budget tracker for refresh operations across modules.
/// Limits total refreshes per time window to avoid excessive resource use.
struct RefreshBudget: Sendable {
    var maxPerMinute: Int = 60
    var recentRefreshes: [Date] = []

    var remainingThisMinute: Int {
        let cutoff = Date().advanced(by: -60)
        let recent = recentRefreshes.filter { $0 > cutoff }
        return max(0, maxPerMinute - recent.count)
    }

    func recordRefresh() -> RefreshBudget {
        var copy = self
        copy.recentRefreshes.append(Date())
        // Prune old entries
        let cutoff = Date().advanced(by: -120)
        copy.recentRefreshes = copy.recentRefreshes.filter { $0 > cutoff }
        return copy
    }
}
