import Foundation

struct RefreshBackoffState: Equatable {
    var failureCount: Int
    var nextRetryDate: Date?
}

final class RefreshScheduler {
    private(set) var states: [ModuleID: RefreshBackoffState] = [:]
    var baseBackoff: TimeInterval = 2
    var maximumBackoff: TimeInterval = 60

    func shouldRefresh(moduleID: ModuleID, policy: RefreshPolicy, lastRefresh: Date?, now: Date = Date()) -> Bool {
        if let nextRetryDate = states[moduleID]?.nextRetryDate,
           nextRetryDate > now {
            return false
        }

        switch policy {
        case .manual:
            return lastRefresh == nil
        case .onLaunch:
            return lastRefresh == nil
        case .interval(let seconds):
            guard let lastRefresh else {
                return true
            }
            return now.timeIntervalSince(lastRefresh) >= seconds
        }
    }

    func recordSuccess(moduleID: ModuleID) {
        states[moduleID] = RefreshBackoffState(failureCount: 0, nextRetryDate: nil)
    }

    @discardableResult
    func recordFailure(moduleID: ModuleID, now: Date = Date()) -> TimeInterval {
        let current = states[moduleID]?.failureCount ?? 0
        let failureCount = current + 1
        let delay = min(maximumBackoff, baseBackoff * pow(2, Double(failureCount - 1)))
        states[moduleID] = RefreshBackoffState(
            failureCount: failureCount,
            nextRetryDate: now.addingTimeInterval(delay)
        )
        return delay
    }
}
