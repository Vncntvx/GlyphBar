import Foundation

final class AppSettingsStore: ObservableObject {
    @Published var enabledModuleIDs: Set<ModuleID> {
        didSet { persist() }
    }

    @Published var moduleOrder: [ModuleID] {
        didSet { persist() }
    }

    @Published var primaryModuleID: ModuleID? {
        didSet { persist() }
    }

    @Published var refreshPolicies: [ModuleID: RefreshPolicy] {
        didSet { persistPolicies() }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    @Published var compactStatusTitle: Bool {
        didSet { defaults.set(compactStatusTitle, forKey: Keys.compactStatusTitle) }
    }

    @Published var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: Keys.showDockIcon) }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabledModuleIDs = Set(defaults.stringArray(forKey: Keys.enabledModuleIDs) ?? [])
        moduleOrder = defaults.stringArray(forKey: Keys.moduleOrder) ?? []
        primaryModuleID = defaults.string(forKey: Keys.primaryModuleID)
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        compactStatusTitle = defaults.object(forKey: Keys.compactStatusTitle) as? Bool ?? false
        showDockIcon = defaults.object(forKey: Keys.showDockIcon) as? Bool ?? true

        if let data = defaults.data(forKey: Keys.refreshPolicies),
           let policies = try? decoder.decode([ModuleID: RefreshPolicy].self, from: data) {
            refreshPolicies = policies
        } else {
            refreshPolicies = [:]
        }
    }

    func registerDefaults(for manifests: [ModuleManifest]) {
        let ids = manifests.map(\.id)
        if moduleOrder.isEmpty {
            moduleOrder = ids
        } else {
            let missing = ids.filter { !moduleOrder.contains($0) }
            moduleOrder.append(contentsOf: missing)
            moduleOrder.removeAll { !ids.contains($0) }
        }

        if enabledModuleIDs.isEmpty {
            enabledModuleIDs = Set(ids)
        }

        if primaryModuleID == nil {
            primaryModuleID = ids.first
        }

        for manifest in manifests where refreshPolicies[manifest.id] == nil {
            refreshPolicies[manifest.id] = manifest.defaultRefreshPolicy
        }
    }

    func isEnabled(_ moduleID: ModuleID) -> Bool {
        enabledModuleIDs.contains(moduleID)
    }

    func setEnabled(_ enabled: Bool, moduleID: ModuleID) {
        if enabled {
            enabledModuleIDs.insert(moduleID)
        } else {
            enabledModuleIDs.remove(moduleID)
        }
    }

    func move(moduleID: ModuleID, direction: Int) {
        guard let index = moduleOrder.firstIndex(of: moduleID) else {
            return
        }

        let destination = index + direction
        guard moduleOrder.indices.contains(destination) else {
            return
        }

        moduleOrder.swapAt(index, destination)
    }

    func resetModuleState(moduleID: ModuleID, cacheStore: CacheStore) {
        cacheStore.clear(moduleID: moduleID)
    }

    func removeModuleState(moduleID: ModuleID) {
        enabledModuleIDs.remove(moduleID)
        moduleOrder.removeAll { $0 == moduleID }
        refreshPolicies.removeValue(forKey: moduleID)
        if primaryModuleID == moduleID {
            primaryModuleID = moduleOrder.first
        }
        persist()
        persistPolicies()
    }

    private func persist() {
        defaults.set(Array(enabledModuleIDs).sorted(), forKey: Keys.enabledModuleIDs)
        defaults.set(moduleOrder, forKey: Keys.moduleOrder)
        if let primaryModuleID {
            defaults.set(primaryModuleID, forKey: Keys.primaryModuleID)
        } else {
            defaults.removeObject(forKey: Keys.primaryModuleID)
        }
    }

    private func persistPolicies() {
        guard let data = try? encoder.encode(refreshPolicies) else {
            return
        }
        defaults.set(data, forKey: Keys.refreshPolicies)
    }

    private enum Keys {
        static let enabledModuleIDs = "settings.enabledModuleIDs"
        static let moduleOrder = "settings.moduleOrder"
        static let primaryModuleID = "settings.primaryModuleID"
        static let refreshPolicies = "settings.refreshPolicies"
        static let launchAtLogin = "settings.launchAtLogin"
        static let compactStatusTitle = "settings.compactStatusTitle"
        static let showDockIcon = "settings.showDockIcon"
    }
}
