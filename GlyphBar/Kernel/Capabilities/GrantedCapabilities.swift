import Foundation

/// The set of capabilities granted to a module by the kernel.
///
/// `bridge` is always present (modules need it to submit effects). All other
/// capabilities are optional — the kernel grants them based on the module's
/// declared manifest. P1 uses simple optional fields; P2 may switch to a
/// type-erased dictionary if modules can declare custom capabilities.
@MainActor
struct GrantedCapabilities {
    let secretStore: ModuleSecretStore?
    let cache: ModuleCacheNamespace?
    let settings: ModuleSettingsNamespace?
    let network: NetworkCapability?
    let fileImport: FileImportCapability?
    let clipboard: ClipboardCapability?
    let logging: LoggingCapability?
    let systemMetrics: SystemMetricsCapability?
    let bridge: ModuleBridge

    init(
        secretStore: ModuleSecretStore? = nil,
        cache: ModuleCacheNamespace? = nil,
        settings: ModuleSettingsNamespace? = nil,
        network: NetworkCapability? = nil,
        fileImport: FileImportCapability? = nil,
        clipboard: ClipboardCapability? = nil,
        logging: LoggingCapability? = nil,
        systemMetrics: SystemMetricsCapability? = nil,
        bridge: ModuleBridge
    ) {
        self.secretStore = secretStore
        self.cache = cache
        self.settings = settings
        self.network = network
        self.fileImport = fileImport
        self.clipboard = clipboard
        self.logging = logging
        self.systemMetrics = systemMetrics
        self.bridge = bridge
    }
}
