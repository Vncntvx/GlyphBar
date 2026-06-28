import Foundation
import Testing
@testable import GlyphBar

struct RefreshSchedulerTests {
    @Test func intervalPolicyWaitsUntilMinimumInterval() {
        let scheduler = RefreshScheduler()
        let now = Date()

        #expect(scheduler.shouldRefresh(moduleID: "clock", policy: .interval(seconds: 60), lastRefresh: now.addingTimeInterval(-10), now: now) == false)
        #expect(scheduler.shouldRefresh(moduleID: "clock", policy: .interval(seconds: 60), lastRefresh: now.addingTimeInterval(-90), now: now) == true)
    }

    @Test func backoffGrowsAndResets() {
        let scheduler = RefreshScheduler()
        scheduler.baseBackoff = 1

        #expect(scheduler.recordFailure(moduleID: "network") == 1)
        #expect(scheduler.recordFailure(moduleID: "network") == 2)

        scheduler.recordSuccess(moduleID: "network")
        #expect(scheduler.states["network"] == RefreshBackoffState(failureCount: 0, nextRetryDate: nil))
    }
}
