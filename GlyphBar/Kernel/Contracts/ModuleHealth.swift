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
}
