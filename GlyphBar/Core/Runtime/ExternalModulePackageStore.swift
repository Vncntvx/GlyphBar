import Foundation

struct ExternalModulePackage {
    let manifest: ExternalModuleManifest
    let moduleManifest: ModuleManifest
    let installURL: URL
    let snapshotURL: URL
}

enum ExternalModulePackageValidator {
    static let manifestFileName = "glyphbar-module.json"
    static let snapshotFileName = "snapshot.json"
    static let supportedSchemaVersion = 1
    static let currentGlyphBarVersion = "1.0"

    static func validatePackage(at url: URL) throws -> ExternalModulePackage {
        let manifestURL = url.appending(path: manifestFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
            throw ExternalModuleError.missingManifest
        }

        let decoder = JSONDecoder()
        let manifest: ExternalModuleManifest
        do {
            manifest = try decoder.decode(ExternalModuleManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw ExternalModuleError.invalidManifest(error.localizedDescription)
        }

        guard manifest.schemaVersion == supportedSchemaVersion else {
            throw ExternalModuleError.unsupportedSchema(manifest.schemaVersion)
        }

        try validateIdentifier(manifest.id)
        try validateCompatibility(manifest)

        let moduleManifest = try manifest.moduleManifest()
        return ExternalModulePackage(
            manifest: manifest,
            moduleManifest: moduleManifest,
            installURL: url,
            snapshotURL: url.appending(path: snapshotFileName)
        )
    }

    private static func validateIdentifier(_ id: ModuleID) throws {
        guard !id.isEmpty else {
            throw ExternalModuleError.invalidManifest("id cannot be empty")
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard id.rangeOfCharacter(from: allowed.inverted) == nil else {
            throw ExternalModuleError.invalidManifest("id may only contain letters, numbers, dots, underscores, and hyphens")
        }
    }

    private static func validateCompatibility(_ manifest: ExternalModuleManifest) throws {
        if let minimum = manifest.minimumGlyphBarVersion,
           compareVersions(currentGlyphBarVersion, minimum) == .orderedAscending {
            throw ExternalModuleError.incompatibleVersion(minimum)
        }

        if let maximum = manifest.maximumGlyphBarVersion,
           compareVersions(currentGlyphBarVersion, maximum) == .orderedDescending {
            throw ExternalModuleError.incompatibleVersion("through \(maximum)")
        }
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(lhs)
        let right = components(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }

        return .orderedSame
    }

    private static func components(_ version: String) -> [Int] {
        version.split { !$0.isNumber }.map { Int($0) ?? 0 }
    }
}

final class ExternalModulePackageStore {
    private let modulesDirectory: URL
    private let fileManager: FileManager

    init(modulesDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let modulesDirectory {
            self.modulesDirectory = modulesDirectory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.modulesDirectory = appSupport
                .appending(path: "GlyphBar", directoryHint: .isDirectory)
                .appending(path: "Modules", directoryHint: .isDirectory)
        }
    }

    func loadPackages() -> [ExternalModulePackage] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: modulesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { try? ExternalModulePackageValidator.validatePackage(at: $0) }
    }

    func validatePackage(at sourceURL: URL) throws -> ExternalModulePackage {
        try ExternalModulePackageValidator.validatePackage(at: sourceURL)
    }

    func importPackage(from sourceURL: URL, replacing: Bool = false) throws -> ExternalModulePackage {
        let package = try validatePackage(at: sourceURL)
        try ensureModulesDirectory()

        let destination = modulesDirectory.appending(path: "\(package.manifest.id).glyphbarmodule", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            guard replacing else {
                throw ExternalModuleError.duplicateModuleID(package.manifest.id)
            }
            try fileManager.removeItem(at: destination)
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
        } catch {
            throw ExternalModuleError.failedCopy(error.localizedDescription)
        }

        return try validatePackage(at: destination)
    }

    func removePackage(moduleID: ModuleID) throws {
        let destination = modulesDirectory.appending(path: "\(moduleID).glyphbarmodule", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else {
            throw ExternalModuleError.notThirdParty(moduleID)
        }
        try fileManager.removeItem(at: destination)
    }

    func storageLocation(moduleID: ModuleID) -> URL {
        modulesDirectory.appending(path: "\(moduleID).glyphbarmodule", directoryHint: .isDirectory)
    }

    private func ensureModulesDirectory() throws {
        guard !fileManager.fileExists(atPath: modulesDirectory.path(percentEncoded: false)) else {
            return
        }
        try fileManager.createDirectory(at: modulesDirectory, withIntermediateDirectories: true)
    }
}
