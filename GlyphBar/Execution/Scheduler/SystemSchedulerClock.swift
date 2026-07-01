import Foundation

@MainActor
final class SystemSchedulerClock: SchedulerClock {
    private var nextID: UInt64 = 1

    func now() -> Date { .now }

    func schedule(after interval: TimeInterval, _ block: @escaping @MainActor @Sendable () -> Void) -> ScheduledHandle {
        let id = nextID
        nextID += 1
        let task = Task { @MainActor in
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
