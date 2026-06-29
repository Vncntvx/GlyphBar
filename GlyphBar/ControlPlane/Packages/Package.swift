import Foundation

/// A versioned, installable module package. Built-in modules are always
/// available; third-party modules are installed from `.glyphbarmodule` packages.
struct Package: Sendable {
    let id: PackageID
    let version: String
    let manifest: ModuleManifest
    let source: PackageSource
    let installURL: URL?

    enum PackageSource: Sendable {
        case builtIn
        case localPackage
        case declarativeJSON
    }
}

/// A factory + metadata for creating module instances from a package.
struct ModuleDefinition: Sendable {
    let typeID: ModuleTypeID
    let packageID: PackageID
    let factory: @Sendable () -> any ModuleContract
}

/// A running instance of a module. Multiple instances can share a type
/// (e.g. two DeepSeek accounts).
struct ModuleInstance: Sendable {
    let id: ModuleInstanceID
    let typeID: ModuleTypeID
    let packageID: PackageID
    let config: [String: String]
}
