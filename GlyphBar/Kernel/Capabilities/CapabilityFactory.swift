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
    private let permissionCenter: PermissionCenter?

    // Shared capabilities (no per-module state needed)
    private lazy var sharedNetwork = NetworkCapability()
    private lazy var sharedSystemMetrics = SystemMetricsCapability()
    private lazy var sharedClipboard = ClipboardCapability()

    init(
        logger: GlyphLogger = GlyphLogger(),
        permissionCenter: PermissionCenter? = nil
    ) {
        self.logger = logger
        self.permissionCenter = permissionCenter
    }

    /// Build `GrantedCapabilities` for a module, granting only the capabilities
    /// declared in its manifest's `permissions` array.
    func makeCapabilities(
        for moduleID: ModuleID,
        permissions: [ModulePermission],
        sourceKind: ModuleSourceKind = .builtIn,
        bridge: ModuleBridge
    ) -> GrantedCapabilities {
        let secretStore: ModuleSecretStore? = nil
        var cache: ModuleCacheNamespace?
        var settings: ModuleSettingsNamespace?
        var network: NetworkCapability?
        var fileImport: FileImportCapability?
        var clipboard: ClipboardCapability?
        var logging: LoggingCapability?
        var systemMetrics: SystemMetricsCapability?

        for permission in permissions where isAllowed(permission, sourceKind: sourceKind) {
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
        sourceKind: ModuleSourceKind = .builtIn,
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
        for permission in manifest.permissions where isAllowed(permission, sourceKind: sourceKind) {
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
        let storageAllowed = isAllowed(.appGroupStorage, sourceKind: sourceKind)
        for capability in manifest.capabilities {
            switch capability {
            case .settings:
                if storageAllowed, settings == nil {
                    settings = ModuleSettingsNamespace(moduleID: moduleID)
                }
            case .cachedState:
                if storageAllowed, cache == nil {
                    cache = ModuleCacheNamespace(moduleID: moduleID)
                }
            case .storage:
                if storageAllowed, cache == nil {
                    cache = ModuleCacheNamespace(moduleID: moduleID)
                }
                if storageAllowed, settings == nil {
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
        if manifest.permissions.contains(.appGroupStorage),
           isAllowed(.appGroupStorage, sourceKind: sourceKind),
           secretStore == nil {
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

    private func isAllowed(_ permission: ModulePermission, sourceKind: ModuleSourceKind) -> Bool {
        switch sourceKind {
        case .builtIn:
            return true
        case .thirdParty:
            guard let permissionCenter else {
                return true
            }
            return permissionCenter.isGranted(permission)
        }
    }
}
