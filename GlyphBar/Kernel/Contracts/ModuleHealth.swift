import Foundation

/// Coarse-grained module health state surfaced to the kernel and presentation layer.
enum ModuleHealth: Sendable, Equatable {
    case healthy
    case degraded(reason: HealthReason)
    case unavailable(reason: HealthReason)
    case blocked(reason: HealthReason)
    case misconfigured(reason: HealthReason)
    case suspended

    enum HealthReason: Sendable, Equatable {
        case missingSecret(String)
        case networkError(String)
        case authFailed
        case rateLimited
        case staleCache(age: TimeInterval)
        case permissionDenied(CapabilityKey)
        case unknown(String)
    }

    /// Whether this health state indicates the module is not functioning normally.
    var isUnhealthy: Bool {
        switch self {
        case .healthy: return false
        case .degraded, .unavailable, .blocked, .misconfigured, .suspended: return true
        }
    }

    /// Whether this health state is terminal (module cannot self-recover).
    var isTerminal: Bool {
        switch self {
        case .healthy, .degraded: return false
        case .unavailable, .blocked, .misconfigured, .suspended: return true
        }
    }
}
