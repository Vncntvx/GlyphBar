import AppKit

@MainActor
final class AppMenuCoordinator: NSObject {
    private let runtime: ModuleRuntime
    private let platformActions: PlatformActions

    init(runtime: ModuleRuntime, platformActions: PlatformActions) {
        self.runtime = runtime
        self.platformActions = platformActions
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "GlyphBar")
        menu.addItem(item("Open GlyphBar", action: #selector(openPanel)))
        menu.addItem(item("Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Refresh All", action: #selector(refreshAll), keyEquivalent: "r"))

        let modulesItem = NSMenuItem(title: "Modules", action: nil, keyEquivalent: "")
        let modulesMenu = NSMenu(title: "Modules")
        for moduleID in runtime.orderedModuleIDs {
            guard let module = runtime.modules[moduleID] else {
                continue
            }
            let moduleItem = NSMenuItem(
                title: shortTitle(module.manifest.displayName),
                action: #selector(toggleModule(_:)),
                keyEquivalent: ""
            )
            moduleItem.target = self
            moduleItem.representedObject = moduleID
            moduleItem.state = runtime.settingsStore.isEnabled(moduleID) ? .on : .off
            modulesMenu.addItem(moduleItem)
        }
        modulesItem.submenu = modulesMenu
        menu.addItem(modulesItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Quit GlyphBar", action: #selector(quit), keyEquivalent: "q"))
        return menu
    }

    private func item(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func openPanel() {
        AppEnvironment.shared.quickPanelCoordinator.show(relativeTo: nil)
    }

    @objc private func openSettings() {
        platformActions.showSettingsWindow()
    }

    @objc private func refreshAll() {
        Task {
            await runtime.refreshEnabledModules()
        }
    }

    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let moduleID = sender.representedObject as? ModuleID else {
            return
        }
        let enabled = !runtime.settingsStore.isEnabled(moduleID)
        runtime.settingsStore.setEnabled(enabled, moduleID: moduleID)
        Task {
            await runtime.refresh(moduleID: moduleID)
        }
    }

    @objc private func quit() {
        platformActions.quit()
    }

    private func shortTitle(_ title: String) -> String {
        if title.count <= 30 {
            return title
        }
        return String(title.prefix(27)) + "..."
    }
}
