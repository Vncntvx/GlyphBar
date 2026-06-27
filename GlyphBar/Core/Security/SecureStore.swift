import Foundation

final class SecureStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func setSecret(_ value: String?, for key: String) {
        let storageKey = self.key(for: key)
        if let value {
            defaults.set(value, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }

    func secret(for key: String) -> String? {
        defaults.string(forKey: self.key(for: key))
    }

    private func key(for rawKey: String) -> String {
        "secure.placeholder.\(rawKey)"
    }
}
