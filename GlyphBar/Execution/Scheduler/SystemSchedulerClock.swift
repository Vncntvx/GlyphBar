import Foundation

final class SystemSchedulerClock: SchedulerClock {
    private var nextID: UInt64 = 1

    func now() -> Date { .now }

    func schedule(after interval: TimeInterval, _ block: @escaping @Sendable () -> Void) -> ScheduledHandle {
        let id = nextID
        nextID += 1
        let task = Task {
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            block()
        }
        return ScheduledHandle.make(id: id) {
            task.cancel()
        }
    }

    func cancel(_ handle: ScheduledHandle) {
        handle.cancel()
    }
}
