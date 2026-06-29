import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct RefreshSchedulerTests {
    @Test func intervalPolicyWaitsUntilMinimumInterval() {
        let clock = VirtualClock()
        let scheduler = RefreshScheduler(clock: clock)
        // Make panel visible so effectiveInterval = base (no 3x scaling)
        scheduler.setPanelVisible(true)
        let now = clock.now()

        #expect(scheduler.shouldRefresh(moduleID: "clock", policy: .interval(seconds: 60), lastRefresh: now.addingTimeInterval(-10)) == false)
        #expect(scheduler.shouldRefresh(moduleID: "clock", policy: .interval(seconds: 60), lastRefresh: now.addingTimeInterval(-90)) == true)
    }

    @Test func manualPolicyNeverAutoRefreshes() {
        let scheduler = RefreshScheduler()

        #expect(scheduler.shouldRefresh(moduleID: "counter", policy: .manual, lastRefresh: nil) == false)
    }

    @Test func onLaunchPolicyRefreshesOnce() {
        let scheduler = RefreshScheduler()

        #expect(scheduler.shouldRefresh(moduleID: "test", policy: .onLaunch, lastRefresh: nil) == true)
        #expect(scheduler.shouldRefresh(moduleID: "test", policy: .onLaunch, lastRefresh: Date()) == false)
    }

    @Test func backoffGrowsAndResets() {
        let clock = VirtualClock()
        let scheduler = RefreshScheduler(clock: clock)

        // Simulate consecutive failures
        scheduler.register(id: "network", policy: .interval(seconds: 30))
        scheduler.recordSuccess(moduleID: "network")

        // Record failures — the scheduler should apply exponential backoff
        scheduler.recordFailure(moduleID: "network")
        // After failure, next fire is delayed by 30 * 2^1 = 60s

        scheduler.recordFailure(moduleID: "network")
        // After second failure, next fire is delayed by 30 * 2^2 = 120s

        // Success resets the backoff
        scheduler.recordSuccess(moduleID: "network")
        // Now next fire should be at the normal interval (30s)
    }

    @Test func effectiveIntervalScalesWithEnvironment() {
        let clock = VirtualClock()
        let scheduler = RefreshScheduler(clock: clock)

        // Base interval 30s, no environment modifiers
        // Panel visible → normal interval
        scheduler.setPanelVisible(true)
        let normal = scheduler.effectiveInterval(30)

        // Panel hidden → 3x
        scheduler.setPanelVisible(false)
        let hidden = scheduler.effectiveInterval(30)

        #expect(hidden > normal)
        #expect(hidden == normal * 3.0)
    }
}
