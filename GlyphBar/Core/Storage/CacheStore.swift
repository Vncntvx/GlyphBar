import Foundation

final class CacheStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ snapshot: ModuleSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: key(for: snapshot.id))
    }

    func load(moduleID: ModuleID) -> ModuleSnapshot? {
        guard let data = defaults.data(forKey: key(for: moduleID)) else {
            return nil
        }

        return try? decoder.decode(ModuleSnapshot.self, from: data)
    }

    func clear(moduleID: ModuleID) {
        defaults.removeObject(forKey: key(for: moduleID))
    }

    private func key(for moduleID: ModuleID) -> String {
        "cache.snapshot.\(moduleID)"
    }
}
