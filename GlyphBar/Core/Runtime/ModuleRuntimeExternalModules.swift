import Foundation

extension ModuleRuntime {
    @discardableResult
    func importModule(from sourceURL: URL, replacing: Bool = false) throws -> ModuleID {
        let package = try registry.importExternalPackage(from: sourceURL, replacing: replacing)
        reloadModules(selecting: package.moduleManifest.id)
        setModuleEnabled(true, moduleID: package.moduleManifest.id)
        return package.moduleManifest.id
    }

    func removeThirdPartyModule(moduleID: ModuleID, removeData: Bool = true) throws {
        guard moduleRecords[moduleID]?.sourceKind == .thirdParty else {
            throw ExternalModuleError.notThirdParty(moduleID)
        }

        settingsStore.setEnabled(false, moduleID: moduleID)
        supervisor.unregister(moduleID: moduleID)
        scheduler.unregister(id: moduleID)
        cancelScheduledLocalTasks(for: moduleID)
        try registry.removeExternalPackage(moduleID: moduleID)
        if removeData {
            cacheStore.clear(moduleID: moduleID)
            widgetBridge.remove(moduleID: moduleID)
        }
        settingsStore.removeModuleState(moduleID: moduleID)
        reloadModules(selecting: enabledModuleIDs.first)
    }

    func storageLocation(for moduleID: ModuleID) -> URL? {
        guard moduleRecords[moduleID]?.sourceKind == .thirdParty else {
            return nil
        }
        return registry.externalStorageLocation(moduleID: moduleID)
    }

    func reloadModules(selecting preferredModuleID: ModuleID?) {
        let records = registry.makeRecords()
        let removedIDs = Set(modules.keys).subtracting(records.keys)
        for id in removedIDs {
            supervisor.unregister(moduleID: id)
            scheduler.unregister(id: id)
            cancelScheduledLocalTasks(for: id)
        }

        moduleRecords = records
        modules = records.mapValues(\.module)

        let manifests = modules.values.map(\.manifest).sorted { $0.displayName < $1.displayName }
        settingsStore.registerDefaults(for: manifests)

        for (id, module) in modules {
            supervisor.register(
                moduleID: id,
                module: module,
                sourceKind: records[id]?.sourceKind ?? .builtIn
            )
        }

        if let preferredModuleID, modules[preferredModuleID] != nil {
            selectedModuleID = preferredModuleID
        } else if let selectedModuleID, modules[selectedModuleID] != nil {
            self.selectedModuleID = selectedModuleID
        } else {
            selectedModuleID = enabledModuleIDs.first ?? orderedModuleIDs.first
        }
    }
}
