import Foundation

/// Abstraction over time for the scheduler. Production uses real time;
/// tests inject a virtual clock that can be advanced deterministically.
@MainActor
protocol SchedulerClock {
    func now() -> Date
    func schedule(after: TimeInterval, _ block: @escaping @MainActor @Sendable () -> Void) -> ScheduledHandle
    func cancel(_ handle: ScheduledHandle)
}

/// Opaque handle for a scheduled callback. Can be cancelled.
struct ScheduledHandle: Equatable, Hashable {
    let id: UInt64

    fileprivate let cancelBlock: @MainActor () -> Void

    static func == (lhs: ScheduledHandle, rhs: ScheduledHandle) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Cancel the scheduled callback.
    @MainActor
    func cancel() {
        cancelBlock()
    }

    /// Create a handle. Only the scheduler clock implementations should call this.
    static func make(id: UInt64, cancel: @escaping @MainActor () -> Void) -> ScheduledHandle {
        ScheduledHandle(id: id, cancelBlock: cancel)
    }
}
