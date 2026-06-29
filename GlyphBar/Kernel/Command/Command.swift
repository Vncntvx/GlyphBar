import Foundation

/// Commands are the kernel's unified input vocabulary.
///
/// P1.2 — defined but not yet wired into the legacy `ModuleRuntime` dispatch path.
/// P1.11 (mechanism A) will route legacy `ModuleAction` / refresh ticks through `Command`.
enum Command: Sendable {
    case refresh(reason: RefreshReason)
    case userAction(actionID: String, payload: ActionPayload?)
    case settingsChanged
    case permissionChanged
    case appBecameActive
    case systemWake
    case networkChanged(reachable: Bool)
    case importData(URL)
    case clearCache
    case contributionTick

    enum RefreshReason: Sendable {
        case manual
        case scheduled
        case launch
        case deepLink
        case cascade
        case networkRestored
        case panelOpened
    }

    struct ActionPayload: Sendable {
        var text: String?
        var data: Data?
    }
}
