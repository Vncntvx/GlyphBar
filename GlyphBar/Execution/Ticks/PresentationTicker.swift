import Foundation

/// Drives the presentation tick at a fixed interval (default 1s).
/// Only runs when there are rotation candidates to cycle through.
/// Replaces the `rotationTimer` that was embedded in `StatusItemController`.
@MainActor
final class PresentationTicker {
    private var timer: Timer?
    private var tickHandler: (() -> Void)?
    private var isRunning = false

    /// Start the ticker with the given interval and tick callback.
    func start(interval: TimeInterval = 1.0, tick: @escaping () -> Void) {
        stop()
        tickHandler = tick
        isRunning = true

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.tickHandler?()
            }
        }
    }

    /// Stop the ticker.
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// Whether the ticker is currently running.
    var running: Bool { isRunning }
}
