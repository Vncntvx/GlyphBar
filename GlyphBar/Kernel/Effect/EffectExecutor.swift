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
    /// Closure to open the settings window. Set by AppEnvironment.
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
            widgetBridge.publish(envelope)

        case .persistDomainState(let data):
            logger.runtime("EffectExecutor: persistDomainState for \(moduleID) (\(data.count) bytes)")

        case .copyToClipboard(let value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)

        case .openURL(let url):
            NSWorkspace.shared.open(url)

        case .showNotice(let message):
            logger.info("Notice for \(moduleID): \(message)")

        case .openModuleSettings:
            openSettingsAction?()
            NSApp.activate()

        case .requestFileImport(let allowedTypes):
            logger.runtime("EffectExecutor: requestFileImport(\(allowedTypes)) for \(moduleID) (capability wiring pending)")

        case .requestRefresh(let reason):
            logger.runtime("EffectExecutor: requestRefresh(\(reason)) for \(moduleID) (kernel wiring pending)")

        case .scheduleLocal(let command, let delay):
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                logger.runtime("EffectExecutor: scheduleLocal fired for \(moduleID)")
            }

        case .networkRequest:
            logger.warning("EffectExecutor: networkRequest effect should use NetworkCapability instead (module \(moduleID))")
        }
    }
}
