import AppKit
import Foundation

/// Drains `Effect` values produced by modules. This is the unified
/// side-effect exit point — all module effects flow through here.
///
/// P1 keeps the executor minimal — each effect maps to one side-effect.
/// P2 may add batching, deduplication, and rate limiting.
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

    init(
        widgetBridge: WidgetDataBridge,
        cacheStore: CacheStore,
        logger: GlyphLogger
    ) {
        self.widgetBridge = widgetBridge
        self.cacheStore = cacheStore
        self.logger = logger
    }

    func execute(_ effect: Effect, for moduleID: String) async {
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
            logger.warning("EffectExecutor: networkRequest effect should use NetworkCapability instead (module \(moduleID))")
        }
    }
}
