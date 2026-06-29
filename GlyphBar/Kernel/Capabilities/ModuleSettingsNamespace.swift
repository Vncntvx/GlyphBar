import Foundation

/// Per-module namespaced settings (UserDefaults-backed). Isolation is by key prefix.
@MainActor
final class ModuleSettingsNamespace: Capability {
    static let declaredKey: CapabilityKey = .settings

    private let moduleID: String
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(moduleID: String, defaults: UserDefaults = AppGroup.defaults()) {
        self.moduleID = moduleID
        self.defaults = defaults
    }

    /// String-typed convenience accessor (most common case for legacy bridges).
    subscript(rawKey: String) -> String? {
        get { defaults.string(forKey: key(for: rawKey)) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: key(for: rawKey))
            } else {
                defaults.removeObject(forKey: key(for: rawKey))
            }
        }
    }

    func get<T: Codable>(_ type: T.Type, forKey rawKey: String) -> T? {
        guard let data = defaults.data(forKey: key(for: rawKey)) else {
            return nil
        }
        return try? decoder.decode(type, from: data)
    }

    func set<T: Codable>(_ value: T?, forKey rawKey: String) {
        let storageKey = key(for: rawKey)
        guard let value else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func key(for rawKey: String) -> String {
        "module.\(moduleID).setting.\(rawKey)"
    }
}
