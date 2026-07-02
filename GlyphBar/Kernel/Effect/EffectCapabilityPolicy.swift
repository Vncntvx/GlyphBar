import Foundation

/// The invocation context in which an Effect is being executed.
/// Some effects (e.g. openURL, copyToClipboard) are only safe when
/// triggered by an explicit user gesture, not by background refresh.
enum EffectInvocationContext: Sendable {
    case userGesture
    case scheduledRefresh
    case backgroundTask
    case moduleStartup
}

/// Whether an effect requires a specific invocation context.
enum EffectContextRequirement: Sendable {
    case any
    case userGestureOnly
}

/// The policy for handling an effect that violates capability constraints.
enum CapabilityViolationPolicy: Sendable {
    /// Fail the test immediately. Used in unit tests and ModuleHarness.
    case failTest
    /// Trigger assertionFailure + show user notice. Used in debug builds.
    case assertAndNotify
    /// Degrade the module and log a severe error. Used in release for built-in modules.
    case degradeModule
    /// Suspend the module and log an audit entry. Used in release for third-party modules.
    case suspendModule
}

/// Describes the capability requirements for a given Effect type.
/// This is the authoritative mapping — EffectExecutor consults this
/// before executing any effect.
enum EffectCapabilityPolicy {
    /// publishSnapshot: no permission required, any context.
    case publishSnapshot
    /// persistDomainState: requires .appGroupStorage, any context.
    case persistDomainState
    /// copyToClipboard: requires .pasteboard, userGesture only.
    case copyToClipboard
    /// openURL: requires .openExternalURLs, userGesture only.
    case openURL
    /// showNotice: no permission required, any context (rate-limited).
    case showNotice
    /// openModuleSettings: no permission required, any context.
    case openModuleSettings
    /// requestFileImport: requires .localFiles, userGesture only.
    case requestFileImport
    /// requestRefresh: no permission required, any context.
    case requestRefresh
    /// scheduleLocal: no permission required, any context.
    /// Scheduling a delayed command is a runtime operation, not a
    /// storage operation — the module already produced the command.
    case scheduleLocal

    /// The permission required to execute this effect, if any.
    var requiredPermission: ModulePermission? {
        switch self {
        case .publishSnapshot: return nil
        case .persistDomainState: return .appGroupStorage
        case .copyToClipboard: return .pasteboard
        case .openURL: return .openExternalURLs
        case .showNotice: return nil
        case .openModuleSettings: return nil
        case .requestFileImport: return .localFiles
        case .requestRefresh: return nil
        case .scheduleLocal: return nil
        }
    }

    /// The invocation context required for this effect.
    var contextRequirement: EffectContextRequirement {
        switch self {
        case .copyToClipboard, .openURL, .requestFileImport:
            return .userGestureOnly
        default:
            return .any
        }
    }

    /// Resolve an Effect value to its policy.
    static func policy(for effect: Effect) -> EffectCapabilityPolicy {
        switch effect {
        case .publishSnapshot: return .publishSnapshot
        case .persistDomainState: return .persistDomainState
        case .copyToClipboard: return .copyToClipboard
        case .openURL: return .openURL
        case .showNotice: return .showNotice
        case .openModuleSettings: return .openModuleSettings
        case .requestFileImport: return .requestFileImport
        case .requestRefresh: return .requestRefresh
        case .scheduleLocal: return .scheduleLocal
        }
    }

    /// Check whether the effect is allowed given the granted permissions
    /// and invocation context.
    func isAllowed(
        grantedPermissions: Set<ModulePermission>,
        context: EffectInvocationContext
    ) -> Bool {
        // Check permission requirement
        if let required = requiredPermission, !grantedPermissions.contains(required) {
            return false
        }
        // Check context requirement
        switch contextRequirement {
        case .any:
            return true
        case .userGestureOnly:
            return context == .userGesture
        }
    }
}
