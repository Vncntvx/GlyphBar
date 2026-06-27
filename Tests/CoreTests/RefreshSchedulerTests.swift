import XCTest
@testable import GlyphBar

final class RefreshSchedulerTests: XCTestCase {
    func testIntervalPolicyWaitsUntilMinimumInterval() {
        let scheduler = RefreshScheduler()
        let now = Date()

        XCTAssertFalse(scheduler.shouldRefresh(moduleID: "clock", policy: .interval(seconds: 60), lastRefresh: now.addingTimeInterval(-10), now: now))
        XCTAssertTrue(scheduler.shouldRefresh(moduleID: "clock", policy: .interval(seconds: 60), lastRefresh: now.addingTimeInterval(-90), now: now))
    }

    func testBackoffGrowsAndResets() {
        let scheduler = RefreshScheduler()
        scheduler.baseBackoff = 1

        XCTAssertEqual(scheduler.recordFailure(moduleID: "network"), 1)
        XCTAssertEqual(scheduler.recordFailure(moduleID: "network"), 2)

        scheduler.recordSuccess(moduleID: "network")
        XCTAssertEqual(scheduler.states["network"], RefreshBackoffState(failureCount: 0, nextRetryDate: nil))
    }
}
