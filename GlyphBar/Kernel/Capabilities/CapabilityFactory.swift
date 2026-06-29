import Foundation

/// Builds `GrantedCapabilities` for a module based on its manifest's declared
/// permissions. This replaces the per-module hardcoded capability construction
/// that was previously in `AppEnvironment`.
///
/// The factory caches shared capability instances (e.g. `NetworkCapability`,
/// `SystemMetricsCapability`) that don't need per-module isolation, and creates
/// fresh per-module instances for namespace-isolated capabilities
/// (`ModuleSecretStore`, `ModuleCacheNamespace`, `ModuleSettingsNamespace`).
@MainActor
final class CapabilityFactory {
    private let logger: GlyphLogger

    // Shared capabilities (no per-module state needed)
    private lazy var sharedNetwork = NetworkCapability()
    private lazy var sharedSystemMetrics = SystemMetricsCapability()
    private lazy var sharedClipboard = ClipboardCapability()

    init(logger: GlyphLogger = GlyphLogger()) {
        self.logger = logger
    }

    /// Build `GrantedCapabilities` for a module, granting only the capabilities
    /// declared in its manifest's `permissions` array.
    func makeCapabilities(
        for moduleID: ModuleID,
        permissions: [ModulePermission],
        bridge: ModuleBridge
    ) -> GrantedCapabilities {
        var secretStore: ModuleSecretStore?
        var cache: ModuleCacheNamespace?
        var settings: ModuleSettingsNamespace?
        var network: NetworkCapability?
        var fileImport: FileImportCapability?
        var clipboard: ClipboardCapability?
        var logging: LoggingCapability?
        var systemMetrics: SystemMetricsCapability?

        for permission in permissions {
            switch permission {
            case .pasteboard:
                clipboard = sharedClipboard
            case .systemMetrics:
                systemMetrics = sharedSystemMetrics
            case .appGroupStorage:
                cache = ModuleCacheNamespace(moduleID: moduleID)
                settings = ModuleSettingsNamespace(moduleID: moduleID)
            case .localFiles:
                fileImport = FileImportCapability(moduleID: moduleID)
            case .openExternalURLs:
                network = sharedNetwork
            case .notifications:
                break  // P1: no runtime capability for notifications yet
            }
        }

        // Modules with cachedState capability always get settings + cache
        // (this covers built-in modules that declare .cachedState but not .appGroupStorage).
        // We check the module's manifest capabilities, not just permissions.
        // For now, built-in modules that need settings/cache get them via
        // the permissions-based grant above. If a module has no permissions
        // but needs settings (e.g. Clock), we still grant them.

        // Always grant logging to every module.
        logging = LoggingCapability(moduleID: moduleID, logger: logger)

        return GrantedCapabilities(
            secretStore: secretStore,
            cache: cache,
            settings: settings,
            network: network,
            fileImport: fileImport,
            clipboard: clipboard,
            logging: logging,
            systemMetrics: systemMetrics,
            bridge: bridge
        )
    }

    /// Build `GrantedCapabilities` for a module, granting capabilities based on
    /// its manifest (both `permissions` and `capabilities` fields).
    ///
    /// This is the full version that also considers `ModuleCapability` declarations
    /// (e.g. `.settings`, `.cachedState`) to grant namespace capabilities even
    /// when the module doesn't declare a corresponding `ModulePermission`.
    func makeCapabilities(
        for moduleID: ModuleID,
        manifest: ModuleManifest,
        bridge: ModuleBridge
    ) -> GrantedCapabilities {
        var secretStore: ModuleSecretStore?
        var cache: ModuleCacheNamespace?
        var settings: ModuleSettingsNamespace?
        var network: NetworkCapability?
        var fileImport: FileImportCapability?
        var clipboard: ClipboardCapability?
        var logging: LoggingCapability?
        var systemMetrics: SystemMetricsCapability?

        // Grant based on permissions
        for permission in manifest.permissions {
            switch permission {
            case .pasteboard:
                clipboard = sharedClipboard
            case .systemMetrics:
                systemMetrics = sharedSystemMetrics
            case .appGroupStorage:
                cache = ModuleCacheNamespace(moduleID: moduleID)
                settings = ModuleSettingsNamespace(moduleID: moduleID)
            case .localFiles:
                fileImport = FileImportCapability(moduleID: moduleID)
            case .openExternalURLs:
                network = sharedNetwork
            case .notifications:
                break
            }
        }

        // Grant based on capabilities (supplements permissions)
        for capability in manifest.capabilities {
            switch capability {
            case .settings:
                if settings == nil {
                    settings = ModuleSettingsNamespace(moduleID: moduleID)
                }
            case .cachedState:
                if cache == nil {
                    cache = ModuleCacheNamespace(moduleID: moduleID)
                }
            case .storage:
                if cache == nil {
                    cache = ModuleCacheNamespace(moduleID: moduleID)
                }
                if settings == nil {
                    settings = ModuleSettingsNamespace(moduleID: moduleID)
                }
            default:
                break
            }
        }

        // DeepSeek needs secretStore + network + fileImport — granted via
        // its manifest permissions [.openExternalURLs, .localFiles, .appGroupStorage]
        // plus the special-case secretStore grant for modules that declare
        // a secret in their health model.
        // For P1, modules that need a secretStore get it if they have
        // .appGroupStorage permission (the only current consumer is DeepSeek).
        if manifest.permissions.contains(.appGroupStorage) && secretStore == nil {
            secretStore = ModuleSecretStore(moduleID: moduleID)
        }

        // Always grant logging.
        logging = LoggingCapability(moduleID: moduleID, logger: logger)

        return GrantedCapabilities(
            secretStore: secretStore,
            cache: cache,
            settings: settings,
            network: network,
            fileImport: fileImport,
            clipboard: clipboard,
            logging: logging,
            systemMetrics: systemMetrics,
            bridge: bridge
        )
    }
}
