import Foundation

/// Commands are the module-level input vocabulary.
/// Only commands that modules actually handle belong here.
/// Application-level operations (enable/disable modules, update permissions,
/// install/uninstall packages) belong in `RuntimeCommand`.
enum Command: Sendable {
    case refresh(reason: RefreshReason)
    case userAction(actionID: String, payload: ActionPayload?)
    case importData(URL)
    case externalEvent(ExternalEvent)

    enum RefreshReason: Sendable {
        case manual
        case scheduled
        case launch
        case deepLink
        case cascade
        case networkRestored
        case panelOpened
        case activation
    }

    struct ActionPayload: Sendable {
        var text: String?
        var data: Data?
    }
}

/// Events delivered to a module from the runtime environment,
/// typically as asynchronous callbacks to earlier Effect requests.
/// Example: a file import completes, delivering the chosen URL.
enum ExternalEvent: Sendable {
    case fileImportCompleted(requestID: UUID, url: URL)
    case fileImportCancelled(requestID: UUID)
}

/// Runtime-level commands that are NOT dispatched to modules.
/// These manage the application's module lifecycle, permissions, and
/// configuration. ModuleRuntime handles these directly; ModuleContract
/// never sees them.
enum RuntimeCommand: Sendable {
    case setModuleEnabled(ModuleID, Bool)
    case updatePermission(ModuleID, ModulePermission, Bool)
    case installModule(at: URL)
    case uninstallModule(ModuleID)
    case reorderModules([ModuleID])
    case setPrimaryModule(ModuleID?)
    case setRefreshPolicy(ModuleID, RefreshPolicy)
}
