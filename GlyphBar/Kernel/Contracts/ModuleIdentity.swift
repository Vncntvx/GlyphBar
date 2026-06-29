import Foundation

/// Unique identifier for a package (e.g. "com.wenjiexu.glyphbar.clock").
struct PackageID: Hashable, Sendable, Codable {
    let value: String
}

/// Type identifier for a module (e.g. "clock", "deepseek").
/// Multiple instances can share the same type.
struct ModuleTypeID: Hashable, Sendable, Codable {
    let value: String
}

/// Unique identifier for a module instance (e.g. "deepseek.default", "deepseek.work").
/// P3 introduces the type→instance split; existing modules default to instance=type.
struct ModuleInstanceID: Hashable, Sendable, Codable {
    let value: String

    /// Convenience: create a default instance ID from a type ID.
    static func `default`(for typeID: ModuleTypeID) -> ModuleInstanceID {
        ModuleInstanceID(value: "\(typeID.value).default")
    }

    /// P3 transition: treat bare module IDs as default instances.
    static func legacy(_ id: ModuleID) -> ModuleInstanceID {
        ModuleInstanceID(value: id)
    }

    /// The bare module ID string (for bridging to P1/P2 APIs).
    var moduleID: ModuleID { value }
}
