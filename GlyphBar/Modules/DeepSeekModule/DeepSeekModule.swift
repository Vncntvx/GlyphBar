import Foundation
import SwiftUI

// MARK: - Module

@MainActor
final class DeepSeekModule: TypedModuleContribution {
    var cached: CachedData?
    var lastErrorMessage: String?
    var cookieExpired = false
    var isExporting = false

    let secretStore: ModuleSecretStore?
    let settings: ModuleSettingsNamespace?
    let cache: ModuleCacheNamespace?
    let network: NetworkCapability?
    let fileImport: FileImportCapability?

    let exportService: UsageExportService
    let store: UsageRecordStore

    init(
        secretStore: ModuleSecretStore? = nil,
        settings: ModuleSettingsNamespace? = nil,
        cache: ModuleCacheNamespace? = nil,
        network: NetworkCapability? = nil,
        fileImport: FileImportCapability? = nil
    ) {
        self.secretStore = secretStore
        self.settings = settings
        self.cache = cache
        self.network = network
        self.fileImport = fileImport
        self.store = UsageRecordStore(cache: cache)
        self.exportService = UsageExportService(secretStore: secretStore, cache: cache)
        loadState()
    }

    var manifest: ModuleManifest { Self.staticManifest }

    static let staticManifest = ModuleManifest(
        id: "deepseek", displayName: "DeepSeek", subtitle: "API balance & usage tracker",
        systemImage: "brain.head.profile", version: "1.2.0", author: "Wenjie Xu",
        capabilities: [.statusItem, .panel, .widgets, .actions, .cachedState, .deepLinks],
        permissions: [.openExternalURLs, .localFiles, .appGroupStorage],
        defaultRefreshPolicy: .interval(seconds: 300),
        actions: [ModuleAction(id: "refresh", title: "Refresh", systemImage: "arrow.clockwise", role: .refresh)],
        widgets: [],
        priority: 100
    )

    // MARK: - TypedModuleContribution

    func handle(
        command: Command,
        capabilities: GrantedCapabilities,
        bridge: ModuleBridge
    ) async -> DomainTransition {
        switch command {
        case .refresh:
            do {
                let snap = try await refreshSnapshot()
                let envelope = ProjectionBuilder.buildEnvelope(from: snap)
                return DomainTransition(
                    effects: [.publishSnapshot(envelope)],
                    health: snap.signals.contains(where: { $0.id == "ds.unav" })
                        ? .misconfigured(reason: .missingSecret("deepseek.apiKey"))
                        : .healthy,
                    refreshProjection: true
                )
            } catch {
                return DomainTransition(
                    effects: [.showNotice(error.localizedDescription)],
                    health: .degraded(reason: .networkError(error.localizedDescription)),
                    refreshProjection: false
                )
            }
        case .userAction(let actionID, let payload):
            switch actionID {
            case "refresh":
                return await handle(command: .refresh(reason: .manual), capabilities: capabilities, bridge: bridge)
            case "setApiKey":
                let key = payload?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !key.isEmpty else { return .empty }
                secretStore?.setSecret(key, for: "deepseek.apiKey")
                lastErrorMessage = nil
            case "clearApiKey":
                cached = nil
                lastErrorMessage = nil
                secretStore?.setSecret(nil, for: "deepseek.apiKey")
            case "setPlatformCookie":
                let cookie = payload?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !cookie.isEmpty else { return .empty }
                secretStore?.setSecret(cookie, for: "deepseek.platformCookie")
                cookieExpired = false
                lastErrorMessage = nil
            case "setRawUserToken":
                let token = payload?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !token.isEmpty else { return .empty }
                secretStore?.setSecret(token, for: "deepseek.rawUserToken")
            case "clearPlatformCookie":
                secretStore?.setSecret(nil, for: "deepseek.platformCookie")
                secretStore?.setSecret(nil, for: "deepseek.rawUserToken")
                cookieExpired = false
            case "requestCSVImport":
                // Request the runtime to present a file chooser.
                // The result arrives via .externalEvent(.fileImportCompleted).
                return DomainTransition(
                    effects: [.requestFileImport(FileImportRequest(allowedTypes: ["csv", "zip"]))],
                    health: .healthy,
                    refreshProjection: false
                )
            case "importUsageItems":
                guard let data = payload?.data,
                      let items = try? JSONDecoder().decode([ParsedUsageItem].self, from: data) else {
                    return .empty
                }
                applyExportedItems(items)
                persistCache()
            case "fetchUsage":
                await fetchUsageExport()
            default:
                return .empty
            }
            return DomainTransition(
                effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: buildSnapshot()))],
                health: .healthy,
                refreshProjection: true
            )
        case .externalEvent(let event):
            switch event {
            case .fileImportCompleted(_, let url):
                importCSV(url: url)
                return DomainTransition(
                    effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: buildSnapshot()))],
                    health: .healthy,
                    refreshProjection: true
                )
            case .fileImportCancelled:
                return .empty
            }
        default:
            return .empty
        }
    }

    func buildProjection() -> ProjectionSet {
        ProjectionBuilder.build(from: buildSnapshot())
    }

    func statusCandidates() -> [StatusCandidate] {
        let snap = buildSnapshot()
        var candidates: [StatusCandidate] = []
        for signal in snap.signals {
            candidates.append(StatusCandidate(
                id: signal.id,
                sourceModule: manifest.id,
                semanticRole: .primary,
                severity: signal.severity,
                priority: signal.priority,
                text: signal.title,
                icon: signal.systemImage,
                createdAt: snap.timestamp,
                expiresAt: nil,
                interruptPolicy: .normal,
                trustLevel: .bundled
            ))
        }
        if let c = cached, c.totalBalance > 0 {
            candidates.append(StatusCandidate(
                id: "ds.balance", sourceModule: manifest.id, semanticRole: .rotation,
                severity: .normal, priority: 50,
                text: String(format: "¥%.2f", c.totalBalance),
                icon: "creditcard", createdAt: snap.timestamp, expiresAt: nil,
                interruptPolicy: .normal, trustLevel: .bundled
            ))
        }
        return candidates
    }

    func panelContent(context: PanelHostContext) -> some View {
        return DeepSeekPanel(
            snapshot: buildSnapshot(), cached: cached, lastErrorMessage: lastErrorMessage,
            cookieExpired: cookieExpired, isExporting: isExporting,
            hasApiKey: secretStore?.secret(for: "deepseek.apiKey")?.isEmpty == false,
            hasCookie: secretStore?.secret(for: "deepseek.platformCookie")?.isEmpty == false,
            onSetKey: { key in
                context.dispatch(.userAction(actionID: "setApiKey", payload: .init(text: key)))
            },
            onClearKey: {
                context.dispatch(.userAction(actionID: "clearApiKey", payload: nil))
            },
            onRefresh: { [weak self] in
                context.dispatch(.refresh(reason: .manual))
                _ = self
            },
            onFetchUsage: { [weak self] in
                context.dispatch(.userAction(actionID: "fetchUsage", payload: nil))
                _ = self
            },
            onSetCookie: { cookie in
                context.dispatch(.userAction(actionID: "setPlatformCookie", payload: .init(text: cookie)))
            },
            onImportCSV: {
                context.dispatch(.userAction(actionID: "requestCSVImport", payload: nil))
            }
        )
    }

}
