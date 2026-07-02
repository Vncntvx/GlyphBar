import AppKit
import Foundation

/// Drains `Effect` values produced by modules. This is the unified
/// side-effect exit point — all module effects flow through here.
@MainActor
final class EffectExecutor {
    private let widgetBridge: WidgetDataBridge
    private let cacheStore: CacheStore
    private let logger: GlyphLogger

    var onSnapshotPublished: ((ModuleID, ModuleSnapshot) -> Void)?
    var onNotice: ((String) -> Void)?
    var requestRefreshAction: ((ModuleID, Command.RefreshReason) async -> Void)?
    var scheduleLocalAction: ((ModuleID, Command, TimeInterval) -> Void)?
    var openSettingsAction: (() -> Void)?

    /// The violation policy determines how unauthorized effects are handled.
    /// Defaults to `.degradeModule` for production; tests should set `.failTest`.
    var violationPolicy: CapabilityViolationPolicy = .degradeModule

    /// Called when a capability violation is detected.
    var onViolation: ((ModuleID, Effect, CapabilityViolationPolicy) -> Void)?

    init(
        widgetBridge: WidgetDataBridge,
        cacheStore: CacheStore,
        logger: GlyphLogger
    ) {
        self.widgetBridge = widgetBridge
        self.cacheStore = cacheStore
        self.logger = logger
    }

    func execute(
        _ effect: Effect,
        for moduleID: String,
        grantedPermissions: Set<ModulePermission> = Set(ModulePermission.allCases),
        invocationContext: EffectInvocationContext = .userGesture
    ) async {
        // Check capability policy before executing.
        let policy = EffectCapabilityPolicy.policy(for: effect)
        if !policy.isAllowed(grantedPermissions: grantedPermissions, context: invocationContext) {
            handleViolation(moduleID: moduleID, effect: effect)
            return
        }

        switch effect {
        case .publishSnapshot(let envelope):
            let snapshot = ProjectionBuilder.buildSnapshot(from: envelope)
            cacheStore.save(snapshot)
            widgetBridge.publish(envelope)
            onSnapshotPublished?(moduleID, snapshot)

        case .persistDomainState(let data):
            logger.runtime("EffectExecutor: persistDomainState for \(moduleID) (\(data.count) bytes)")

        case .copyToClipboard(let value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            onNotice?("Copied")

        case .openURL(let url):
            NSWorkspace.shared.open(url)

        case .showNotice(let message):
            onNotice?(message)
            logger.info("Notice for \(moduleID): \(message)")

        case .openModuleSettings:
            openSettingsAction?()
            NSApp.activate()

        case .requestFileImport(let allowedTypes):
            logger.runtime("EffectExecutor: requestFileImport(\(allowedTypes)) for \(moduleID) (capability wiring pending)")

        case .requestRefresh(let reason):
            if let requestRefreshAction {
                await requestRefreshAction(moduleID, reason)
            } else {
                logger.runtime("EffectExecutor: requestRefresh(\(reason)) for \(moduleID) has no runtime handler")
            }

        case .scheduleLocal(let command, let delay):
            if let scheduleLocalAction {
                scheduleLocalAction(moduleID, command, delay)
            } else {
                logger.runtime("EffectExecutor: scheduleLocal(\(delay)) for \(moduleID) has no runtime handler")
            }

        case .networkRequest:
            logger.warning("EffectExecutor: networkRequest effect is deprecated — use NetworkCapability instead (module \(moduleID))")
        }
    }

    // MARK: - Violation Handling

    private func handleViolation(moduleID: ModuleID, effect: Effect) {
        let policyName: String
        switch violationPolicy {
        case .failTest:
            policyName = "failTest"
            // In test mode, we record the violation so the test harness can assert.
            // The harness checks `violations` after dispatch.
            onViolation?(moduleID, effect, .failTest)
        case .assertAndNotify:
            policyName = "assertAndNotify"
            assertionFailure("Capability violation: module \(moduleID) attempted unauthorized effect \(effect)")
            onViolation?(moduleID, effect, .assertAndNotify)
        case .degradeModule:
            policyName = "degradeModule"
            logger.error("CAPABILITY VIOLATION: module \(moduleID) attempted unauthorized effect \(effect) — degrading module")
            onViolation?(moduleID, effect, .degradeModule)
        case .suspendModule:
            policyName = "suspendModule"
            logger.error("CAPABILITY VIOLATION: module \(moduleID) attempted unauthorized effect \(effect) — suspending module (audit)")
            onViolation?(moduleID, effect, .suspendModule)
        }
    }
}
