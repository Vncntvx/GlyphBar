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
struct ModuleInstanceID: Hashable, Sendable, Codable {
    let value: String

    /// Convenience: create a default instance ID from a type ID.
    static func `default`(for typeID: ModuleTypeID) -> ModuleInstanceID {
        ModuleInstanceID(value: "\(typeID.value).default")
    }

    /// Create an instance ID from the module ID used by the current runtime.
    static func fromModuleID(_ id: ModuleID) -> ModuleInstanceID {
        ModuleInstanceID(value: id)
    }

    /// The module ID string used by the current runtime.
    var moduleID: ModuleID { value }
}
