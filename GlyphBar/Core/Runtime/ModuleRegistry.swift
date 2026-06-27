import Foundation
import SwiftUI

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
    let module: any StatusModule
    let sourceKind: ModuleSourceKind
    let installURL: URL?
    let trustState: ModuleTrustState

    var canRemove: Bool {
        sourceKind == .thirdParty
    }
}

enum ExternalModuleError: LocalizedError, Equatable {
    case missingManifest
    case invalidManifest(String)
    case incompatibleVersion(String)
    case unsupportedSchema(Int)
    case duplicateModuleID(ModuleID)
    case duplicateBuiltInID(ModuleID)
    case failedCopy(String)
    case notThirdParty(ModuleID)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "The selected module does not contain glyphbar-module.json."
        case .invalidManifest(let reason):
            return "The module manifest is invalid: \(reason)"
        case .incompatibleVersion(let requirement):
            return "This module requires GlyphBar \(requirement)."
        case .unsupportedSchema(let version):
            return "Module schema \(version) is not supported."
        case .duplicateModuleID(let id):
            return "A third-party module with ID \(id) is already installed."
        case .duplicateBuiltInID(let id):
            return "Module ID \(id) is reserved by a built-in module."
        case .failedCopy(let reason):
            return "GlyphBar could not copy the module: \(reason)"
        case .notThirdParty(let id):
            return "\(id) is not a removable third-party module."
        }
    }
}

struct ExternalRefreshPolicy: Codable, Hashable, Sendable {
    var type: String
    var seconds: TimeInterval?

    func refreshPolicy() throws -> RefreshPolicy {
        switch type.lowercased() {
        case "manual":
            return .manual
        case "launch", "onlaunch", "on-launch":
            return .onLaunch
        case "interval":
            guard let seconds, seconds > 0 else {
                throw ExternalModuleError.invalidManifest("interval refreshPolicy requires positive seconds")
            }
            return .interval(seconds: seconds)
        default:
            throw ExternalModuleError.invalidManifest("unsupported refreshPolicy type \(type)")
        }
    }
}

enum ExternalModuleActionKind: String, Codable, Hashable, Sendable {
    case copy
    case openURL
    case deepLink
    case refresh
}

struct ExternalModuleActionDefinition: Codable, Hashable, Sendable {
    var id: String
    var title: String
    var systemImage: String
    var role: ModuleAction.Role?
    var kind: ExternalModuleActionKind
    var value: String?

    var moduleAction: ModuleAction {
        ModuleAction(id: id, title: title, systemImage: systemImage, role: role ?? .standard)
    }
}

struct ExternalPanelDescriptor: Codable, Hashable, Sendable {
    var metricOrder: [String]?
    var noteTitle: String?
    var metadataKeys: [String]?
}

struct ExternalModuleManifest: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var id: ModuleID
    var displayName: String
    var subtitle: String
    var systemImage: String
    var version: String
    var author: String
    var minimumGlyphBarVersion: String?
    var maximumGlyphBarVersion: String?
    var capabilities: [ModuleCapability]
    var permissions: [ModulePermission]
    var refreshPolicy: ExternalRefreshPolicy?
    var actions: [ExternalModuleActionDefinition]
    var widgets: [ModuleWidgetDescriptor]
    var panel: ExternalPanelDescriptor?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(ModuleID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        systemImage = try container.decode(String.self, forKey: .systemImage)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "1.0.0"
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? "Unknown"
        minimumGlyphBarVersion = try container.decodeIfPresent(String.self, forKey: .minimumGlyphBarVersion)
        maximumGlyphBarVersion = try container.decodeIfPresent(String.self, forKey: .maximumGlyphBarVersion)
        capabilities = try container.decodeIfPresent([ModuleCapability].self, forKey: .capabilities) ?? [.panel]
        permissions = try container.decodeIfPresent([ModulePermission].self, forKey: .permissions) ?? []
        refreshPolicy = try container.decodeIfPresent(ExternalRefreshPolicy.self, forKey: .refreshPolicy)
        actions = try container.decodeIfPresent([ExternalModuleActionDefinition].self, forKey: .actions) ?? []
        widgets = try container.decodeIfPresent([ModuleWidgetDescriptor].self, forKey: .widgets) ?? []
        panel = try container.decodeIfPresent(ExternalPanelDescriptor.self, forKey: .panel)
    }

    init(
        schemaVersion: Int,
        id: ModuleID,
        displayName: String,
        subtitle: String,
        systemImage: String,
        version: String,
        author: String,
        minimumGlyphBarVersion: String? = nil,
        maximumGlyphBarVersion: String? = nil,
        capabilities: [ModuleCapability],
        permissions: [ModulePermission],
        refreshPolicy: ExternalRefreshPolicy? = nil,
        actions: [ExternalModuleActionDefinition] = [],
        widgets: [ModuleWidgetDescriptor] = [],
        panel: ExternalPanelDescriptor? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.version = version
        self.author = author
        self.minimumGlyphBarVersion = minimumGlyphBarVersion
        self.maximumGlyphBarVersion = maximumGlyphBarVersion
        self.capabilities = capabilities
        self.permissions = permissions
        self.refreshPolicy = refreshPolicy
        self.actions = actions
        self.widgets = widgets
        self.panel = panel
    }

    func moduleManifest() throws -> ModuleManifest {
        let refreshPolicy = try refreshPolicy?.refreshPolicy() ?? .manual
        return ModuleManifest(
            id: id,
            displayName: displayName,
            subtitle: subtitle,
            systemImage: systemImage,
            version: version,
            author: author,
            compatibility: ModuleCompatibility(
                minimumGlyphBarVersion: minimumGlyphBarVersion ?? "1.0",
                maximumGlyphBarVersion: maximumGlyphBarVersion
            ),
            capabilities: capabilities,
            permissions: permissions,
            defaultRefreshPolicy: refreshPolicy,
            actions: actions.map(\.moduleAction),
            widgets: widgets
        )
    }
}

private struct ExternalSnapshotSignal: Codable, Hashable, Sendable {
    var title: String
    var message: String?
    var systemImage: String
    var severity: Severity
    var priority: Int?

    var signal: StatusSignal {
        StatusSignal(
            title: title,
            message: message ?? "",
            systemImage: systemImage,
            severity: severity,
            priority: priority ?? 0
        )
    }
}

private struct ExternalModuleSnapshot: Codable, Hashable, Sendable {
    var title: String
    var subtitle: String
    var systemImage: String?
    var unavailableReason: String?
    var signals: [ExternalSnapshotSignal]?
    var metrics: [String: Double]?
    var notes: [String]?
    var metadata: [String: String]?

    func snapshot(moduleID: ModuleID, fallbackSystemImage: String) -> ModuleSnapshot {
        ModuleSnapshot(
            id: moduleID,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage ?? fallbackSystemImage,
            freshness: unavailableReason.map { .unavailable($0) } ?? .fresh,
            signals: signals?.map(\.signal) ?? [],
            metrics: metrics ?? [:],
            notes: notes ?? [],
            metadata: metadata ?? [:]
        )
    }
}

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
        let manifestURL = url.appendingPathComponent(manifestFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
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
            snapshotURL: url.appendingPathComponent(snapshotFileName)
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
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.modulesDirectory = appSupport
                .appendingPathComponent("GlyphBar", isDirectory: true)
                .appendingPathComponent("Modules", isDirectory: true)
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

        let destination = modulesDirectory.appendingPathComponent("\(package.manifest.id).glyphbarmodule", isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) {
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
        let destination = modulesDirectory.appendingPathComponent("\(moduleID).glyphbarmodule", isDirectory: true)
        guard fileManager.fileExists(atPath: destination.path) else {
            throw ExternalModuleError.notThirdParty(moduleID)
        }
        try fileManager.removeItem(at: destination)
    }

    func storageLocation(moduleID: ModuleID) -> URL {
        modulesDirectory.appendingPathComponent("\(moduleID).glyphbarmodule", isDirectory: true)
    }

    private func ensureModulesDirectory() throws {
        guard !fileManager.fileExists(atPath: modulesDirectory.path) else {
            return
        }
        try fileManager.createDirectory(at: modulesDirectory, withIntermediateDirectories: true)
    }
}

@MainActor
final class ModuleRegistry {
    typealias Factory = () -> any StatusModule

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

@MainActor
final class DeclarativeModule: StatusModule {
    private let package: ExternalModulePackage
    private let decoder = JSONDecoder()

    init(package: ExternalModulePackage) {
        self.package = package
    }

    var manifest: ModuleManifest {
        package.moduleManifest
    }

    func refresh(context: ModuleContext) async throws -> ModuleSnapshot {
        guard FileManager.default.fileExists(atPath: package.snapshotURL.path) else {
            return ModuleSnapshot(
                id: manifest.id,
                title: manifest.displayName,
                subtitle: "No snapshot.json in module package",
                systemImage: manifest.systemImage,
                freshness: .unavailable("No cached snapshot")
            )
        }

        let snapshot = try decoder.decode(ExternalModuleSnapshot.self, from: Data(contentsOf: package.snapshotURL))
        return snapshot.snapshot(moduleID: manifest.id, fallbackSystemImage: manifest.systemImage)
    }

    func handle(action: ModuleAction, context: ModuleContext) async throws -> ModuleEvent {
        guard let definition = package.manifest.actions.first(where: { $0.id == action.id }) else {
            return .none
        }

        switch definition.kind {
        case .copy:
            return .copyToPasteboard(definition.value ?? "")
        case .openURL, .deepLink:
            guard let value = definition.value,
                  let url = URL(string: value) else {
                return .none
            }
            context.platformActions.open(url)
            return .none
        case .refresh:
            return .refreshRequested(manifest.id)
        }
    }

    func makePanelView(context: ModuleContext, snapshot: ModuleSnapshot?) -> AnyView {
        AnyView(DeclarativeModulePanel(manifest: manifest, descriptor: package.manifest.panel, snapshot: snapshot))
    }
}

private struct DeclarativeModulePanel: View {
    let manifest: ModuleManifest
    let descriptor: ExternalPanelDescriptor?
    let snapshot: ModuleSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !orderedMetrics.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    ForEach(orderedMetrics, id: \.0) { key, value in
                        GlyphMetricCard(title: key.capitalized, value: formatted(value), systemImage: "chart.bar")
                    }
                }
            }

            if let notes = snapshot?.notes, !notes.isEmpty {
                GlyphCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(descriptor?.noteTitle ?? "Notes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(notes, id: \.self) { note in
                            Text(note)
                                .font(.callout)
                                .lineLimit(2)
                        }
                    }
                }
            }

            if !orderedMetadata.isEmpty {
                GlyphCard {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(orderedMetadata, id: \.0) { key, value in
                            HStack {
                                Text(key.capitalized)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(value)
                                    .textSelection(.enabled)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private var orderedMetrics: [(String, Double)] {
        let metrics = snapshot?.metrics ?? [:]
        if let order = descriptor?.metricOrder, !order.isEmpty {
            return order.compactMap { key in
                metrics[key].map { (key, $0) }
            }
        }
        return metrics.sorted { $0.key < $1.key }
    }

    private var orderedMetadata: [(String, String)] {
        let metadata = snapshot?.metadata ?? [:]
        if let keys = descriptor?.metadataKeys, !keys.isEmpty {
            return keys.compactMap { key in
                metadata[key].map { (key, $0) }
            }
        }
        return metadata.sorted { $0.key < $1.key }
    }

    private func formatted(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}
