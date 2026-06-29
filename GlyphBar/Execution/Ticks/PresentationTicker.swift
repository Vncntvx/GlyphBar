import Foundation

/// Drives the presentation tick at a fixed interval (default 1s).
/// Only runs when there are rotation candidates to cycle through.
/// Replaces the `rotationTimer` that was embedded in `StatusItemController`.
@MainActor
final class PresentationTicker {
    private var tickTask: Task<Void, Never>?
    private(set) var isRunning = false

    /// Start the ticker with the given interval and tick callback.
    func start(interval: TimeInterval = 1.0, tick: @escaping () -> Void) {
        stop()
        isRunning = true
        tickTask = Task { [weak self] in
            while self?.isRunning == true {
                try? await Task.sleep(for: .seconds(interval))
                guard self?.isRunning == true else { return }
                tick()
            }
        }
    }

    /// Stop the ticker.
    func stop() {
        tickTask?.cancel()
        tickTask = nil
        isRunning = false
    }

    /// Whether the ticker is currently running.
    var running: Bool { isRunning }
}
