import Foundation

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

struct ExternalSnapshotSignal: Codable, Hashable, Sendable {
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

struct ExternalModuleSnapshot: Codable, Hashable, Sendable {
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
