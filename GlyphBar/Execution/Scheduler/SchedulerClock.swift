import Foundation

/// Abstraction over time for the scheduler. Production uses real time;
/// tests inject a virtual clock that can be advanced deterministically.
protocol SchedulerClock: Sendable {
    func now() -> Date
    func schedule(after: TimeInterval, _ block: @escaping @Sendable () -> Void) -> ScheduledHandle
    func cancel(_ handle: ScheduledHandle)
}

/// Opaque handle for a scheduled callback. Can be cancelled.
struct ScheduledHandle: Sendable, Equatable, Hashable {
    let id: UInt64

    fileprivate let cancelBlock: @Sendable () -> Void

    static func == (lhs: ScheduledHandle, rhs: ScheduledHandle) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Create a handle. Only the scheduler clock implementations should call this.
    static func make(id: UInt64, cancel: @escaping @Sendable () -> Void) -> ScheduledHandle {
        ScheduledHandle(id: id, cancelBlock: cancel)
    }
}
