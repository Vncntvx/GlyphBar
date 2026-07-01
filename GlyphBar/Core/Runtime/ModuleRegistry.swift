import Foundation

enum ModuleSourceKind: String, Codable, Hashable, Sendable {
    case builtIn
    case thirdParty

    var title: String {
        switch self {
        case .builtIn: return "Built-in"
        case .thirdParty: return "Third-party"
        }
    }
}

enum ModuleTrustState: String, Codable, Hashable, Sendable {
    case bundled
    case unsignedLocalPackage
    case invalid

    var title: String {
        switch self {
        case .bundled: return "Bundled"
        case .unsignedLocalPackage: return "Unsigned Local Package"
        case .invalid: return "Invalid"
        }
    }
}

struct ModuleRecord: Identifiable {
    let id: ModuleID
    let module: any ModuleContract
    let sourceKind: ModuleSourceKind
    let installURL: URL?
    let trustState: ModuleTrustState

    var canRemove: Bool {
        sourceKind == .thirdParty
    }
}

@MainActor
final class ModuleRegistry {
    typealias Factory = () -> any ModuleContract

    private var factories: [ModuleID: Factory] = [:]
    private let externalStore: ExternalModulePackageStore

    init(externalStore: ExternalModulePackageStore = ExternalModulePackageStore()) {
        self.externalStore = externalStore
    }

    func register(_ factory: @escaping Factory) {
        let module = factory()
        factories[module.manifest.id] = factory
    }

    func makeRecords() -> [ModuleID: ModuleRecord] {
        var records = Dictionary(uniqueKeysWithValues: factories.map { id, factory in
            let module = factory()
            return (
                id,
                ModuleRecord(
                    id: id,
                    module: module,
                    sourceKind: .builtIn,
                    installURL: nil,
                    trustState: .bundled
                )
            )
        })

        for package in externalStore.loadPackages() where records[package.moduleManifest.id] == nil {
            let module = DeclarativeModule(package: package)
            records[package.moduleManifest.id] = ModuleRecord(
                id: package.moduleManifest.id,
                module: module,
                sourceKind: .thirdParty,
                installURL: package.installURL,
                trustState: .unsignedLocalPackage
            )
        }

        return records
    }

    func importExternalPackage(from sourceURL: URL, replacing: Bool = false) throws -> ExternalModulePackage {
        let package = try externalStore.validatePackage(at: sourceURL)
        if factories[package.moduleManifest.id] != nil {
            throw ExternalModuleError.duplicateBuiltInID(package.moduleManifest.id)
        }
        return try externalStore.importPackage(from: sourceURL, replacing: replacing)
    }

    func removeExternalPackage(moduleID: ModuleID) throws {
        try externalStore.removePackage(moduleID: moduleID)
    }

    func externalStorageLocation(moduleID: ModuleID) -> URL {
        externalStore.storageLocation(moduleID: moduleID)
    }
}
