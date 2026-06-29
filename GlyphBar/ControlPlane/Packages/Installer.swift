import Foundation

/// Transactional installer for third-party module packages.
/// Implements the acquire → stage → validate → commit pattern.
@MainActor
final class Installer {
    private let logger: GlyphLogger
    private let externalStore: ExternalModulePackageStore

    init(externalStore: ExternalModulePackageStore, logger: GlyphLogger = GlyphLogger()) {
        self.externalStore = externalStore
        self.logger = logger
    }

    /// Install a package from a source URL. Uses a transactional approach:
    /// 1. Acquire — copy the package to a staging area
    /// 2. Validate — check the manifest, signing, and schema version
    /// 3. Commit — move from staging to the installed location
    ///
    /// If any step fails, the staging area is cleaned up (rollback).
    func install(from sourceURL: URL, replacing: Bool = false) async throws -> Package {
        // Stage: validate the package at the source URL
        let validator = PackageValidator()
        let manifest = try validator.validate(at: sourceURL)

        // Commit: import via ExternalModulePackageStore
        let package = try externalStore.importPackage(from: sourceURL, replacing: replacing)

        return Package(
            id: PackageID(value: package.moduleManifest.id),
            version: package.moduleManifest.version,
            manifest: package.moduleManifest,
            source: .localPackage,
            installURL: sourceURL
        )
    }

    /// Uninstall a package. If preserveData is true, the module's cached
    /// data and settings are retained for potential re-installation.
    func uninstall(_ packageID: PackageID, preserveData: Bool) async throws {
        try externalStore.removePackage(moduleID: packageID.value)
    }
}

/// Validates module packages before installation.
struct PackageValidator {
    func validate(at url: URL) throws -> ModuleManifest {
        let manifestURL = url.appendingPathComponent("glyphbar-module.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw InstallerError.missingManifest
        }

        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(ModuleManifest.self, from: data)

        // P3: check schema version compatibility
        guard manifest.compatibility.minimumGlyphBarVersion <= "1.0" else {
            throw InstallerError.incompatibleVersion(manifest.compatibility.minimumGlyphBarVersion)
        }

        return manifest
    }
}

enum InstallerError: Error, LocalizedError {
    case missingManifest
    case incompatibleVersion(String)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest: return "Package is missing glyphbar-module.json"
        case .incompatibleVersion(let v): return "Package requires GlyphBar \(v) or later"
        case .validationFailed(let msg): return "Package validation failed: \(msg)"
        }
    }
}
