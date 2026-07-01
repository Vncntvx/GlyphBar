import Foundation

/// Virtual clock for deterministic testing. Tests advance time explicitly
/// and observe scheduled callbacks fire in order.
@MainActor
final class VirtualClock: SchedulerClock {
    private var currentTime: Date = Date(timeIntervalSince1970: 1000000)
    private var nextHandleID: UInt64 = 1
    private var pending: [(fireAt: Date, handleID: UInt64, block: @MainActor @Sendable () -> Void)] = []

    func now() -> Date { currentTime }

    func schedule(after: TimeInterval, _ block: @escaping @MainActor @Sendable () -> Void) -> ScheduledHandle {
        let handleID = nextHandleID
        nextHandleID += 1
        let fireAt = currentTime.advanced(by: after)
        pending.append((fireAt: fireAt, handleID: handleID, block: block))
        return ScheduledHandle.make(
            id: handleID,
            cancel: { [weak self] in
                self?.pending.removeAll { $0.handleID == handleID }
            }
        )
    }

    func cancel(_ handle: ScheduledHandle) {
        pending.removeAll { $0.handleID == handle.id }
    }

    /// Advance time by the given interval, firing all scheduled callbacks
    /// whose fire-at time has been reached.
    func advance(by interval: TimeInterval) {
        currentTime = currentTime.advanced(by: interval)
        fireDueCallbacks()
    }

    /// Advance time to a specific date.
    func advance(to date: Date) {
        currentTime = date
        fireDueCallbacks()
    }

    private func fireDueCallbacks() {
        let due = pending.filter { $0.fireAt <= currentTime }
        for item in due.sorted(by: { $0.fireAt < $1.fireAt }) {
            item.block()
            pending.removeAll { $0.handleID == item.handleID }
        }
    }

    /// Number of pending scheduled callbacks.
    var pendingCount: Int { pending.count }

    /// Next scheduled fire time, or nil if no pending callbacks.
    var nextFireTime: Date? { pending.map(\.fireAt).min() }
}
