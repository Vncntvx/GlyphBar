import Foundation

/// Production scheduler clock using DispatchSourceTimer for precise,
/// cancellable scheduling.
final class SystemSchedulerClock: SchedulerClock {
    private var nextID: UInt64 = 1
    private var timers: [UInt64: DispatchSourceTimer] = [:]

    func now() -> Date { Date() }

    func schedule(after interval: TimeInterval, _ block: @escaping @Sendable () -> Void) -> ScheduledHandle {
        let id = nextID
        nextID += 1
        let timer = DispatchSource.makeTimerSource(flags: .strict)
        timer.schedule(deadline: .now() + interval, leeway: .milliseconds(50))
        timer.setEventHandler {
            block()
        }
        timer.resume()
        timers[id] = timer
        return ScheduledHandle.make(
            id: id,
            cancel: { [weak timerRef = timer] in
                timerRef?.cancel()
            }
        )
    }

    func cancel(_ handle: ScheduledHandle) {
        if let timer = timers[handle.id] {
            timer.cancel()
            timers.removeValue(forKey: handle.id)
        }
    }
}
