import Foundation

/// Pure state-transition function for module lifecycle.
/// Each module has an operational state that evolves through events.
/// The state machine is independent of any actor or runtime — it can
/// be tested exhaustively with pure inputs.
enum ModuleOperationalState: Sendable, Equatable {
    case installed       // Package present, not yet loaded
    case loaded          // Module object created, not yet started
    case starting        // First refresh in progress
    case idle            // Waiting for next scheduled refresh
    case refreshing      // Refresh in progress
    case ready           // Has at least one successful snapshot
    case degraded        // Partial functionality (e.g. missing secret)
    case suspended       // Temporarily paused (e.g. permission revoked)
    case failed          // Last refresh failed terminally
    case stopping        // Graceful shutdown in progress
    case uninstalled     // Package removed

    enum Event: Sendable, Equatable {
        case load
        case start
        case refreshBegan
        case refreshSucceeded
        case refreshFailed(terminal: Bool)
        case suspend
        case resume
        case stop
        case uninstall
        case degrade
        case recover
    }

    /// Apply an event, returning the new state. Invalid transitions
    /// return the current state unchanged (idempotent).
    mutating func apply(_ event: Event) -> ModuleOperationalState {
        switch (self, event) {
        // Normal lifecycle
        case (.installed, .load):              self = .loaded
        case (.loaded, .start):                self = .starting
        case (.starting, .refreshBegan):       self = .refreshing
        case (.starting, .refreshSucceeded):   self = .ready
        case (.starting, .refreshFailed(let terminal)):  self = terminal ? .failed : .idle
        case (.idle, .refreshBegan):           self = .refreshing
        case (.idle, .suspend):                self = .suspended
        case (.refreshing, .refreshSucceeded): self = .ready
        case (.refreshing, .refreshFailed(let terminal)): self = terminal ? .failed : .idle
        case (.ready, .refreshBegan):          self = .refreshing
        case (.ready, .suspend):               self = .suspended
        case (.ready, .degrade):               self = .degraded

        // Recovery paths
        case (.failed, .resume):               self = .idle
        case (.failed, .recover):              self = .idle
        case (.failed, .uninstall):            self = .uninstalled
        case (.suspended, .resume):            self = .idle
        case (.suspended, .uninstall):         self = .uninstalled
        case (.degraded, .recover):            self = .ready
        case (.degraded, .suspend):            self = .suspended
        case (.degraded, .refreshFailed(let terminal)): self = terminal ? .failed : .degraded

        // Shutdown
        case (_, .stop):                       self = .stopping
        case (.stopping, .uninstall):          self = .uninstalled
        case (.stopping, .refreshSucceeded):   self = .stopping  // drain in-flight
        case (.stopping, .refreshFailed):      self = .stopping  // drain in-flight

        // Invalid transitions — stay in current state
        default: break
        }
        return self
    }

    /// Whether the module is in a state where refresh can begin.
    var canRefresh: Bool {
        switch self {
        case .idle, .starting, .ready, .degraded:
            return true
        case .installed, .loaded, .refreshing, .suspended, .failed, .stopping, .uninstalled:
            return false
        }
    }

    /// Whether the module has useful data to show.
    var hasData: Bool {
        switch self {
        case .ready, .refreshing, .degraded, .idle:
            return true
        default:
            return false
        }
    }
}
