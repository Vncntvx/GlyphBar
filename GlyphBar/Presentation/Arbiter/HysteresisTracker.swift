import Foundation

/// Two-threshold hysteresis with min-duration gating. Used by the arbiter to
/// prevent flicker when a value oscillates around a single threshold.
///
/// `enterThreshold > exitThreshold` (typical). The state flips to `true` only
/// after `value >= enterThreshold` for at least `minDurationToEnter`; it flips
/// to `false` only after `value < exitThreshold` for at least `minDurationToExit`.
struct HysteresisTracker {
    let enterThreshold: Double
    let exitThreshold: Double
    let minDurationToEnter: TimeInterval
    let minDurationToExit: TimeInterval

    private(set) var currentState: Bool = false
    private(set) var since: Date = Date()
    private var pendingState: Bool?

    init(
        enterThreshold: Double,
        exitThreshold: Double,
        minDurationToEnter: TimeInterval = 0,
        minDurationToExit: TimeInterval = 0
    ) {
        self.enterThreshold = enterThreshold
        self.exitThreshold = exitThreshold
        self.minDurationToEnter = minDurationToEnter
        self.minDurationToExit = minDurationToExit
    }

    /// Returns the new state after applying `value` at time `now`.
    mutating func update(value: Double, now: Date) -> Bool {
        let desired: Bool
        if currentState {
            desired = value >= exitThreshold
        } else {
            desired = value >= enterThreshold
        }

        if desired == currentState {
            pendingState = nil
            return currentState
        }

        if pendingState != desired {
            pendingState = desired
            since = now
        }

        let required: TimeInterval = desired ? minDurationToEnter : minDurationToExit
        if now.timeIntervalSince(since) >= required {
            currentState = desired
            pendingState = nil
        }
        return currentState
    }
}
