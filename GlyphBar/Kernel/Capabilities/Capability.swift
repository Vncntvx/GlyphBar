import Foundation

/// Stable identifier for a capability slot. Modules request capabilities by key
/// in their manifest; the kernel grants concrete instances via `GrantedCapabilities`.
enum CapabilityKey: String, Sendable, CaseIterable, Codable {
    case secretStore
    case cache
    case settings
    case network
    case fileImport
    case clipboard
    case logging
    case systemMetrics
}

/// Marker protocol for capability implementations.
///
/// P1 only: all capabilities are `@MainActor final class`. P2 may introduce
/// actor-backed capabilities; the protocol will still hold.
@MainActor
protocol Capability: AnyObject {
    static var declaredKey: CapabilityKey { get }
}
