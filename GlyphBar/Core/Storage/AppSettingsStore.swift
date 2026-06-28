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

    @Published var statusRotationEnabled: Bool {
        didSet { defaults.set(statusRotationEnabled, forKey: Keys.statusRotationEnabled) }
    }

    @Published var statusRotationInterval: Int {
        didSet { defaults.set(statusRotationInterval, forKey: Keys.statusRotationInterval) }
    }

    @Published var rotationModuleIDs: Set<ModuleID> {
        didSet { defaults.set(Array(rotationModuleIDs).sorted(), forKey: Keys.rotationModuleIDs) }
    }

    @Published var rotationItemIDs: [ModuleID: Set<String>] {
        didSet { persistRotationItems() }
    }

    @Published var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: Keys.showDockIcon) }
    }

    @Published var colorScheme: String {
        didSet { defaults.set(colorScheme, forKey: Keys.colorScheme) }
    }

    @Published var pinPanel: Bool {
        didSet { defaults.set(pinPanel, forKey: Keys.pinPanel) }
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
        statusRotationEnabled = defaults.object(forKey: Keys.statusRotationEnabled) as? Bool ?? false
        statusRotationInterval = defaults.object(forKey: Keys.statusRotationInterval) as? Int ?? 5
        rotationModuleIDs = Set(defaults.stringArray(forKey: Keys.rotationModuleIDs) ?? [])
        if let data = defaults.data(forKey: Keys.rotationItemIDs),
           let items = try? decoder.decode([ModuleID: Set<String>].self, from: data) {
            rotationItemIDs = items
        } else {
            rotationItemIDs = [:]
        }
        showDockIcon = defaults.object(forKey: Keys.showDockIcon) as? Bool ?? true
        colorScheme = defaults.string(forKey: Keys.colorScheme) ?? "system"
        pinPanel = defaults.object(forKey: Keys.pinPanel) as? Bool ?? false

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
            // Don't auto-enable all modules — user enables them explicitly in Settings.
        } else {
            let newIDs = ids.filter { !enabledModuleIDs.contains($0) }
            if !newIDs.isEmpty {
                enabledModuleIDs.formUnion(newIDs)
            }
        }

        if primaryModuleID == nil {
            primaryModuleID = ids.first
        }

        for manifest in manifests where refreshPolicies[manifest.id] == nil {
            refreshPolicies[manifest.id] = manifest.defaultRefreshPolicy
        }

        // Auto-populate rotation defaults for new modules
        if rotationModuleIDs.isEmpty {
            rotationModuleIDs = Set(ids)
        } else {
            let newIDs = ids.filter { !rotationModuleIDs.contains($0) }
            if !newIDs.isEmpty { rotationModuleIDs.formUnion(newIDs) }
        }
        for id in ids where rotationItemIDs[id] == nil {
            rotationItemIDs[id] = ["default"]
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

    func setRefreshPolicy(_ policy: RefreshPolicy, for moduleID: ModuleID) {
        refreshPolicies[moduleID] = policy
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

    private func persistRotationItems() {
        if let data = try? encoder.encode(rotationItemIDs) {
            defaults.set(data, forKey: Keys.rotationItemIDs)
        }
    }

    private enum Keys {
        static let enabledModuleIDs = "settings.enabledModuleIDs"
        static let moduleOrder = "settings.moduleOrder"
        static let primaryModuleID = "settings.primaryModuleID"
        static let refreshPolicies = "settings.refreshPolicies"
        static let launchAtLogin = "settings.launchAtLogin"
        static let statusRotationEnabled = "settings.statusRotationEnabled"
        static let statusRotationInterval = "settings.statusRotationInterval"
        static let rotationModuleIDs = "settings.rotationModuleIDs"
        static let rotationItemIDs = "settings.rotationItemIDs"
        static let showDockIcon = "settings.showDockIcon"
        static let colorScheme = "settings.colorScheme"
        static let pinPanel = "settings.pinPanel"
    }
}
