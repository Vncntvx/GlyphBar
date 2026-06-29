import Foundation

/// Per-module namespaced cache for opaque domain state (the bytes a module
/// chooses to persist between launches). Isolation is by key prefix.
@MainActor
final class ModuleCacheNamespace: Capability {
    static let declaredKey: CapabilityKey = .cache

    private let moduleID: String
    private let defaults: UserDefaults

    init(moduleID: String, defaults: UserDefaults = AppGroup.defaults()) {
        self.moduleID = moduleID
        self.defaults = defaults
    }

    func saveDomainState(_ data: Data) {
        defaults.set(data, forKey: key)
    }

    func loadDomainState() -> Data? {
        defaults.data(forKey: key)
    }

    func clearDomainState() {
        defaults.removeObject(forKey: key)
    }

    private var key: String {
        "module.\(moduleID).domainState"
    }
}
