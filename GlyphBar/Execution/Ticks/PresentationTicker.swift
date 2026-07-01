import Foundation

/// Drives the presentation tick at a fixed interval (default 1s).
/// Only runs when there are rotation candidates to cycle through.
/// Replaces the `rotationTimer` that was embedded in `StatusItemController`.
@MainActor
final class PresentationTicker {
    private let clock: SchedulerClock
    private var handle: ScheduledHandle?
    private var interval: TimeInterval = 1.0
    private var tick: (() -> Void)?
    private(set) var isRunning = false

    init(clock: SchedulerClock = SystemSchedulerClock()) {
        self.clock = clock
    }

    /// Start the ticker with the given interval and tick callback.
    func start(interval: TimeInterval = 1.0, tick: @escaping () -> Void) {
        stop()
        self.interval = interval
        self.tick = tick
        isRunning = true
        scheduleNextTick()
    }

    private func scheduleNextTick() {
        handle = clock.schedule(after: interval) { [weak self] in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.tick?()
                self.scheduleNextTick()
            }
        }
    }

    /// Stop the ticker.
    func stop() {
        if let handle {
            clock.cancel(handle)
        }
        handle = nil
        tick = nil
        isRunning = false
    }

    /// Whether the ticker is currently running.
    var running: Bool { isRunning }
}
