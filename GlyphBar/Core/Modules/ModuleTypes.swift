import Foundation

typealias ModuleID = String

enum Severity: String, Codable, CaseIterable, Comparable, Sendable {
    case normal
    case info
    case warning
    case critical

    var rank: Int {
        switch self {
        case .normal: return 0
        case .info: return 1
        case .warning: return 2
        case .critical: return 3
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rank < rhs.rank
    }
}

enum ModuleCapability: String, Codable, CaseIterable, Sendable {
    case statusItem
    case panel
    case widgets
    case actions
    case settings
    case cachedState
    case permissions
    case deepLinks
    case storage
}

enum ModulePermission: String, Codable, CaseIterable, Sendable {
    case pasteboard
    case notifications
    case systemMetrics
    case appGroupStorage
    case openExternalURLs
    case localFiles
}

struct ModuleAction: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var systemImage: String
    var role: Role

    enum Role: String, Codable, Sendable {
        case standard
        case destructive
        case refresh
    }

    init(id: String, title: String, systemImage: String, role: Role = .standard) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.role = role
    }
}

struct ModuleWidgetDescriptor: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var supportedFamilies: [String]
}

struct ModuleCompatibility: Codable, Hashable, Sendable {
    var minimumGlyphBarVersion: String
    var maximumGlyphBarVersion: String?

    static let current = ModuleCompatibility(minimumGlyphBarVersion: "1.0", maximumGlyphBarVersion: nil)
}

struct ModuleManifest: Identifiable, Codable, Hashable, Sendable {
    let id: ModuleID
    var displayName: String
    var subtitle: String
    var systemImage: String
    var version: String
    var author: String
    var compatibility: ModuleCompatibility
    var capabilities: [ModuleCapability]
    var permissions: [ModulePermission]
    var defaultRefreshPolicy: RefreshPolicy
    var actions: [ModuleAction]
    var widgets: [ModuleWidgetDescriptor]

    init(
        id: ModuleID,
        displayName: String,
        subtitle: String,
        systemImage: String,
        version: String = "1.0.0",
        author: String = "GlyphBar",
        compatibility: ModuleCompatibility = .current,
        capabilities: [ModuleCapability],
        permissions: [ModulePermission],
        defaultRefreshPolicy: RefreshPolicy,
        actions: [ModuleAction],
        widgets: [ModuleWidgetDescriptor]
    ) {
        self.id = id
        self.displayName = displayName
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.version = version
        self.author = author
        self.compatibility = compatibility
        self.capabilities = capabilities
        self.permissions = permissions
        self.defaultRefreshPolicy = defaultRefreshPolicy
        self.actions = actions
        self.widgets = widgets
    }
}

enum RefreshPolicy: Codable, Hashable, Sendable {
    case manual
    case onLaunch
    case interval(seconds: TimeInterval)

    var minimumInterval: TimeInterval? {
        switch self {
        case .manual:
            return nil
        case .onLaunch:
            return 0
        case .interval(let seconds):
            return seconds
        }
    }
}

enum SnapshotFreshness: Codable, Hashable, Sendable {
    case fresh
    case stale(Date)
    case unavailable(String)

    var isAvailable: Bool {
        switch self {
        case .fresh, .stale:
            return true
        case .unavailable:
            return false
        }
    }
}

struct StatusSignal: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var message: String
    var systemImage: String
    var severity: Severity
    var priority: Int

    init(
        id: String = UUID().uuidString,
        title: String,
        message: String = "",
        systemImage: String,
        severity: Severity,
        priority: Int = 0
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.severity = severity
        self.priority = priority
    }
}

struct ModuleSnapshot: Identifiable, Codable, Hashable, Sendable {
    let id: ModuleID
    var title: String
    var subtitle: String
    var systemImage: String
    var timestamp: Date
    var freshness: SnapshotFreshness
    var signals: [StatusSignal]
    var metrics: [String: Double]
    var notes: [String]
    var metadata: [String: String]

    init(
        id: ModuleID,
        title: String,
        subtitle: String,
        systemImage: String,
        timestamp: Date = Date(),
        freshness: SnapshotFreshness = .fresh,
        signals: [StatusSignal] = [],
        metrics: [String: Double] = [:],
        notes: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.timestamp = timestamp
        self.freshness = freshness
        self.signals = signals
        self.metrics = metrics
        self.notes = notes
        self.metadata = metadata
    }

    func markedStale(reason: String) -> ModuleSnapshot {
        var copy = self
        copy.freshness = .stale(Date())
        copy.signals.append(StatusSignal(
            title: "Stale",
            message: reason,
            systemImage: "clock.badge.exclamationmark",
            severity: .warning,
            priority: 10
        ))
        return copy
    }
}

enum ModuleEvent: Equatable {
    case none
    case didUpdateSnapshot(ModuleSnapshot)
    case copyToPasteboard(String)
    case refreshRequested(ModuleID)
    case stateChanged(ModuleID)
    case userNotice(String)
    case openSettings(ModuleID)
}

struct ModuleDeepLink: Equatable, Sendable {
    var moduleID: ModuleID
    var actionID: String?
    var section: Section

    enum Section: Equatable, Sendable {
        case overview
        case settings
        case widget
        case action
    }
}
