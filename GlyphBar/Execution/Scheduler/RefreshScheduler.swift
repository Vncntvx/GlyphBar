import Foundation

/// Clock-driven refresh scheduler with environment awareness.
/// Replaces the legacy `RefreshScheduler` (which was just a backoff state machine).
///
/// The scheduler registers modules with their refresh policies, then uses
/// a `SchedulerClock` to fire `Command.refresh(.scheduled)` at the right time.
/// Environment factors (panel visibility, power, network, app activity)
/// scale the effective interval.
@MainActor
final class RefreshScheduler {
    private let clock: SchedulerClock
    private var jobs: [ModuleID: RefreshJob] = [:]
    private var scheduledHandles: [ModuleID: ScheduledHandle] = [:]
    private var budget: RefreshBudget = RefreshBudget()
    private var env: SystemEnvironmentMonitor?

    // Environment awareness
    private var isPanelVisible = false
    private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var isNetworkAvailable = true
    private var isAppActive = true

    /// Called when the scheduler wants to dispatch a refresh command.
    /// Wired to `Supervisor.dispatch(.refresh(.scheduled), for:)`.
    var onRefreshDue: ((ModuleID) -> Void)?

    init(clock: SchedulerClock = SystemSchedulerClock()) {
        self.clock = clock
    }

    /// Set the environment monitor for awareness.
    func setEnvironmentMonitor(_ monitor: SystemEnvironmentMonitor) {
        self.env = monitor
        monitor.subscribe { [weak self] event in
            Task { @MainActor in
                self?.onSystemEvent(event)
            }
        }
    }

    /// Register a module for scheduled refreshes.
    func register(id: ModuleID, policy: RefreshPolicy, priority: RefreshScheduler.Priority = .normal) {
        let job = RefreshJob(
            moduleID: id,
            policy: policy,
            priority: priority,
            lastFireAt: nil,
            consecutiveFailures: 0
        )
        jobs[id] = job
        scheduleNextFire(for: id)
    }

    /// Unregister a module from scheduled refreshes.
    func unregister(id: ModuleID) {
        if let handle = scheduledHandles[id] {
            clock.cancel(handle)
            scheduledHandles.removeValue(forKey: id)
        }
        jobs.removeValue(forKey: id)
    }

    /// Record a successful refresh for the given module.
    func recordSuccess(moduleID: ModuleID) {
        guard var job = jobs[moduleID] else { return }
        job.lastFireAt = clock.now()
        job.consecutiveFailures = 0
        jobs[moduleID] = job
        budget = budget.recordRefresh()
        scheduleNextFire(for: moduleID)
    }

    /// Record a failed refresh for the given module.
    func recordFailure(moduleID: ModuleID) {
        guard var job = jobs[moduleID] else { return }
        job.consecutiveFailures += 1
        jobs[moduleID] = job
        scheduleNextFire(for: moduleID)
    }

    /// Check whether a module should refresh now (respecting policy and backoff).
    func shouldRefresh(moduleID: ModuleID, policy: RefreshPolicy, lastRefresh: Date?) -> Bool {
        guard budget.remainingThisMinute > 0 else { return false }

        switch policy {
        case .manual:
            return false
        case .onLaunch:
            return lastRefresh == nil
        case .interval(let seconds):
            guard let lastRefresh else { return true }
            let effective = effectiveInterval(seconds)
            return clock.now().timeIntervalSince(lastRefresh) >= effective
        }
    }

    /// Handle a system event that may affect refresh scheduling.
    func onSystemEvent(_ event: SystemEvent) {
        switch event {
        case .appBecameActive:
            isAppActive = true
            rescheduleAll()
        case .appResignedActive:
            isAppActive = false
        case .systemWake:
            isAppActive = true
            rescheduleAll()
        case .systemSleep:
            isAppActive = false
        case .networkChanged(let reachable):
            isNetworkAvailable = reachable
            if reachable { rescheduleAll() }
        case .powerStateChanged(_, let lowPower):
            isLowPower = lowPower
            rescheduleAll()
        }
    }

    // MARK: - Private

    private func scheduleNextFire(for moduleID: ModuleID) {
        // Cancel any existing scheduled fire
        if let handle = scheduledHandles[moduleID] {
            clock.cancel(handle)
            scheduledHandles.removeValue(forKey: moduleID)
        }

        guard let job = jobs[moduleID] else { return }

        guard case .interval(let baseSeconds) = job.policy else { return }
        guard isNetworkAvailable else { return }  // No refreshes when offline

        let effective = effectiveInterval(baseSeconds)

        // Apply backoff for consecutive failures
        let backoffFactor = pow(2.0, Double(min(job.consecutiveFailures, 5)))
        let intervalWithBackoff = effective * backoffFactor

        let handle = clock.schedule(after: intervalWithBackoff) { [weak self] in
            Task { @MainActor in
                self?.fireRefresh(for: moduleID)
            }
        }
        scheduledHandles[moduleID] = handle
    }

    private func fireRefresh(for moduleID: ModuleID) {
        scheduledHandles.removeValue(forKey: moduleID)
        onRefreshDue?(moduleID)
    }

    private func rescheduleAll() {
        for moduleID in jobs.keys {
            scheduleNextFire(for: moduleID)
        }
    }

    /// Compute the effective interval based on environment factors.
    /// - Panel closed: 3x
    /// - Low power: 2x
    /// - Network unavailable: skip (∞)
    /// - App inactive: 2x
    func effectiveInterval(_ base: TimeInterval) -> TimeInterval {
        var interval = base
        if !isPanelVisible { interval *= 3.0 }
        if isLowPower { interval *= 2.0 }
        if !isAppActive { interval *= 2.0 }
        return interval
    }

    /// Notify the scheduler that the panel is now visible/hidden.
    func setPanelVisible(_ visible: Bool) {
        let changed = visible != isPanelVisible
        isPanelVisible = visible
        if changed { rescheduleAll() }
    }

    enum Priority: Int, Comparable {
        case background = 0
        case normal = 1
        case userFacing = 2

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}
