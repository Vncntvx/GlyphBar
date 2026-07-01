import Foundation

enum DeepLinkRoute: Equatable {
    case appPanel
    case appSettings
    case appModules
    case appLogs
    case appImportModule
    case appRefreshAll
    case module(ModuleID)
    case moduleSettings(ModuleID)
    case moduleWidget(ModuleID)
    case moduleAction(moduleID: ModuleID, actionID: String)
}

@MainActor
final class DeepLinkRouter {
    private weak var runtime: ModuleRuntime?
    private let openPanel: () -> Void
    private let openSettings: (SettingsSection, ModuleID?) -> Void
    private let openLogs: () -> Void
    private let importModule: () -> Void
    private let showModule: (ModuleID) -> Void
    private let logger: GlyphLogger

    init(
        runtime: ModuleRuntime,
        logger: GlyphLogger,
        openPanel: @escaping () -> Void,
        openSettings: @escaping (SettingsSection, ModuleID?) -> Void,
        openLogs: @escaping () -> Void,
        importModule: @escaping () -> Void,
        showModule: @escaping (ModuleID) -> Void
    ) {
        self.runtime = runtime
        self.logger = logger
        self.openPanel = openPanel
        self.openSettings = openSettings
        self.openLogs = openLogs
        self.importModule = importModule
        self.showModule = showModule
    }

    nonisolated static func parse(_ url: URL) -> DeepLinkRoute? {
        guard url.scheme?.lowercased() == "glyphbar",
              let host = url.host?.lowercased() else {
            return nil
        }

        let components = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "app":
            guard let destination = components.first?.lowercased() else {
                return nil
            }
            switch destination {
            case "panel": return .appPanel
            case "settings": return .appSettings
            case "modules": return .appModules
            case "logs": return .appLogs
            case "import-module", "import": return .appImportModule
            case "refresh", "refresh-all": return .appRefreshAll
            default: return nil
            }

        case "module":
            guard let rawModuleID = components.first else {
                return nil
            }
            let moduleID = canonicalModuleID(rawModuleID)

            if components.count == 1 {
                return .module(moduleID)
            }

            if components.count == 2 {
                switch components[1].lowercased() {
                case "settings": return .moduleSettings(moduleID)
                case "widget": return .moduleWidget(moduleID)
                default: return nil
                }
            }

            if components.count == 3,
               components[1].lowercased() == "action" {
                return .moduleAction(moduleID: moduleID, actionID: components[2])
            }

            return nil

        default:
            return nil
        }
    }

    nonisolated private static func canonicalModuleID(_ moduleID: String) -> String {
        switch moduleID {
        case "system-pulse":
            return "systemPulse"
        case "notes-quick":
            return "notesQuick"
        case "network-mock":
            return "networkMock"
        default:
            return moduleID
        }
    }

    func route(_ url: URL) {
        guard let route = Self.parse(url) else {
            logger.warning("Ignored invalid deep link: \(url.absoluteString)")
            return
        }

        logger.route("Routing \(url.absoluteString)")

        switch route {
        case .appPanel:
            openPanel()
        case .appSettings:
            openSettings(.general, nil)
        case .appModules:
            openSettings(.modules, nil)
        case .appLogs:
            openLogs()
        case .appImportModule:
            importModule()
        case .appRefreshAll:
            Task {
                await runtime?.refreshEnabledModules()
            }
        case .module(let moduleID), .moduleWidget(let moduleID):
            runtime?.setSelectedModule(moduleID)
            showModule(moduleID)
        case .moduleSettings(let moduleID):
            runtime?.setSelectedModule(moduleID)
            openSettings(.modules, moduleID)
        case .moduleAction(let moduleID, let actionID):
            guard let action = runtime?.modules[moduleID]?.manifest.actions.first(where: { $0.id == actionID }) else {
                logger.warning("Ignored missing action \(actionID) for \(moduleID)")
                return
            }
            logger.route("Dispatching action \(actionID) for \(moduleID)")
            Task {
                await runtime?.dispatch(action: action, moduleID: moduleID)
            }
        }
    }
}
