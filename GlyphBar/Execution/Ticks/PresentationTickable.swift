import Foundation

/// Protocol for modules that need time-driven display updates without
/// triggering a full data refresh. Clock is the primary example: its
/// seconds display ticks every second, but its data (timezone, format)
/// only changes on user action.
///
/// P2: This separates "presentation tick" from "data refresh",
/// preventing Clock from flooding the refresh pipeline at 1Hz.
@MainActor
protocol PresentationTickable: ModuleContract {
    /// Recompute the display projection based on the current time and trigger.
    /// This MUST NOT produce side effects — it returns an updated ProjectionSet
    /// that the caller (Arbiter) uses for display.
    func presentationTick(trigger: PresentationTrigger, projection: ProjectionSet) -> ProjectionSet
}

/// What caused the presentation tick.
enum PresentationTrigger: Sendable {
    case timerTick
    case panelOpened
    case panelClosed
    case appBecameActive
    case systemWake
}
