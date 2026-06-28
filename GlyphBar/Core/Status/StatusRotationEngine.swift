import Foundation

/// Drives status bar content rotation across enabled modules and their selected items.
@MainActor
final class StatusRotationEngine {
    private var items: [RotationItem] = []
    private var index = 0

    var count: Int { items.count }

    /// Rebuild the rotation list from snapshots and per-module item preferences.
    func rebuild(
        modules: [ModuleID: any StatusModule],
        snapshots: [ModuleID: ModuleSnapshot],
        enabledIDs: Set<ModuleID>,
        rotationModuleIDs: Set<ModuleID>,
        rotationItemIDs: [ModuleID: Set<String>]
    ) {
        items = []
        for id in enabledIDs.sorted() {
            guard rotationModuleIDs.contains(id),
                  let module = modules[id],
                  let snap = snapshots[id] else { continue }
            let descriptors = module.statusBarRotationItems(snapshot: snap)
            let selectedIDs = rotationItemIDs[id]
            let filtered = descriptors.filter { desc in
                if let sel = selectedIDs { return sel.contains(desc.id) }
                return true // no stored preference → show all
            }
            let toAdd = filtered.isEmpty ? descriptors.prefix(1) : filtered[...]
            for desc in toAdd {
                items.append(RotationItem(
                    moduleID: id,
                    title: desc.title,
                    systemImage: desc.systemImage,
                    tooltip: desc.tooltip
                ))
            }
        }
        if index >= items.count { index = 0 }
    }

    /// Returns the next presentation and advances the index.
    func tick() -> StatusItemPresentation? {
        guard !items.isEmpty else { return nil }
        let item = items[index]
        index = (index + 1) % items.count
        return StatusItemPresentation(
            title: item.title,
            systemImage: item.systemImage,
            severity: .normal,
            tooltip: item.tooltip
        )
    }
}

struct RotationItem {
    let moduleID: ModuleID
    let title: String
    let systemImage: String
    let tooltip: String
}
