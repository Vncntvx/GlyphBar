import Foundation

/// Drains `Effect` values produced by modules. P1 only constructs this; P1.11
/// wires it into `Kernel`, and P1.13 wires `Kernel` into `ModuleRuntime`.
///
/// P1 keeps the executor minimal — each effect maps to one side-effect. P2 may
/// add batching, deduplication, and rate limiting.
@MainActor
final class EffectExecutor {
    private let widgetBridge: WidgetDataBridge
    private let cacheStore: CacheStore
    private let platformActions: PlatformActions
    private let logger: GlyphLogger

    init(
        widgetBridge: WidgetDataBridge,
        cacheStore: CacheStore,
        platformActions: PlatformActions,
        logger: GlyphLogger
    ) {
        self.widgetBridge = widgetBridge
        self.cacheStore = cacheStore
        self.platformActions = platformActions
        self.logger = logger
    }

    func execute(_ effect: Effect, for moduleID: String) async {
        switch effect {
        case .publishSnapshot(let envelope):
            // P1.12: WidgetSnapshotBridge accepts envelopes directly and
            // triggers `WidgetCenter.shared.reloadAllTimelines()`.
            widgetBridge.publish(envelope)

        case .persistDomainState(let data):
            // P1.13 wires this to `ModuleCacheNamespace.saveDomainState`. For
            // now, we persist via the legacy `CacheStore` path is not applicable
            // (domain state is module-specific bytes, not a ModuleSnapshot).
            logger.runtime("EffectExecutor: persistDomainState for \(moduleID) (\(data.count) bytes)")

        case .copyToClipboard(let value):
            platformActions.copyToPasteboard(value)

        case .openURL(let url):
            platformActions.open(url)

        case .showNotice(let message):
            // P1: route through logger. P1.11 will surface this via ModuleRuntime.userNotice.
            logger.info("Notice for \(moduleID): \(message)")

        case .openModuleSettings:
            platformActions.showSettingsWindow()

        case .requestFileImport(let allowedTypes):
            // P1.13 wires this to `FileImportCapability`. The executor does not
            // directly present panels — it routes through capabilities.
            logger.runtime("EffectExecutor: requestFileImport(\(allowedTypes)) for \(moduleID) (capability wiring pending P1.13)")

        case .requestRefresh(let reason):
            // P1.11 wires this to `Kernel.dispatch(.refresh(reason:))`.
            logger.runtime("EffectExecutor: requestRefresh(\(reason)) for \(moduleID) (kernel wiring pending P1.11)")

        case .scheduleLocal(let command, let delay):
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                // P1.11: kernel.dispatch(command, for: moduleID)
                logger.runtime("EffectExecutor: scheduleLocal fired for \(moduleID)")
            }

        case .networkRequest:
            // Network requests should go through `NetworkCapability`, not via
            // effects. If we get here, it's a programming error.
            logger.warning("EffectExecutor: networkRequest effect should use NetworkCapability instead (module \(moduleID))")
        }
    }
}
