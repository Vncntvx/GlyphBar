import Foundation

/// Commands are the kernel's unified input vocabulary.
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
