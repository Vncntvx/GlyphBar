import Foundation
import SwiftUI
import OSLog

private let log = Logger(subsystem: "com.wenjiexu.GlyphBar", category: "DeepSeek")

// MARK: - Module

@MainActor
final class DeepSeekModule: TypedModuleContribution {
    private var cached: CachedData?
    private var lastErrorMessage: String?
    private var cookieExpired = false
    private var isExporting = false

    private let apiBase = "https://api.deepseek.com"

    private let secretStore: ModuleSecretStore?
    private let settings: ModuleSettingsNamespace?
    private let cache: ModuleCacheNamespace?
    private let network: NetworkCapability?
    private let fileImport: FileImportCapability?

    private let exportService: UsageExportService
    private let store: UsageRecordStore

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

    /// Validates an API key by calling the /user/balance endpoint.
    static func validateApiKey(_ key: String, network: NetworkCapability) async throws {
        let apiBase = "https://api.deepseek.com"
        let request = NetworkRequest(
            url: URL(string: "\(apiBase)/user/balance")!,
            headers: [
                "Authorization": "Bearer \(key)",
                "Accept": "application/json"
            ]
        )
        let (_, http) = try await network.send(request)
        if http.statusCode == 401 { throw DeepSeekError.invalidKey }
        if http.statusCode == 403 { throw DeepSeekError.forbidden }
        if http.statusCode == 429 { throw DeepSeekError.rateLimited }
        if http.statusCode != 200 { throw DeepSeekError.apiError(http.statusCode, "") }
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
        case .importData(let url):
            importCSV(url: url)
            return DomainTransition(
                effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: buildSnapshot()))],
                health: .healthy,
                refreshProjection: true
            )
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
            onImportCSV: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, let cap = self.fileImport else { return }
                    if let url = cap.requestImport(allowedTypes: ["csv", "zip"]) {
                        context.dispatch(.importData(url))
                    }
                }
            }
        )
    }

    // MARK: - Internals

    /// Refresh path used by command handling.
    private func refreshSnapshot() async throws -> ModuleSnapshot {
        lastErrorMessage = nil; cookieExpired = false

        let apiKey = secretStore?.secret(for: "deepseek.apiKey") ?? ""
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cached = nil
            return ModuleSnapshot(
                id: manifest.id,
                title: "DeepSeek",
                subtitle: "API key not configured",
                systemImage: manifest.systemImage,
                freshness: .unavailable("API key not configured"),
                signals: [
                    StatusSignal(
                        id: "ds.unav",
                        title: "Missing API Key",
                        message: "Configure a DeepSeek API key to refresh balance.",
                        systemImage: "key.slash",
                        severity: .warning,
                        priority: 90
                    )
                ]
            )
        }
        let balance = try? await fetchBalance(apiKey: apiKey)
        let totalBal = Double(balance?.balanceInfos.first?.totalBalance ?? "0") ?? 0
        let granted = Double(balance?.balanceInfos.first?.grantedBalance ?? "0") ?? 0
        let topped = Double(balance?.balanceInfos.first?.toppedUpBalance ?? "0") ?? 0

        let existing = cached
        cached = CachedData(
            totalBalance: totalBal, grantedBalance: granted, toppedUpBalance: topped,
            isAvailable: balance?.isAvailable ?? false,
            todayCost: existing?.todayCost ?? 0, monthlyCost: existing?.monthlyCost ?? 0,
            totalTokens: existing?.totalTokens ?? 0, totalCacheHit: existing?.totalCacheHit ?? 0, totalRequests: existing?.totalRequests ?? 0,
            modelV4FlashTokens: existing?.modelV4FlashTokens ?? 0, modelV4FlashCost: existing?.modelV4FlashCost ?? 0,
            modelV4FlashCacheHit: existing?.modelV4FlashCacheHit ?? 0, modelV4FlashCacheMiss: existing?.modelV4FlashCacheMiss ?? 0,
            modelV4ProTokens: existing?.modelV4ProTokens ?? 0, modelV4ProCost: existing?.modelV4ProCost ?? 0,
            modelV4ProCacheHit: existing?.modelV4ProCacheHit ?? 0, modelV4ProCacheMiss: existing?.modelV4ProCacheMiss ?? 0,
            dailyItems: existing?.dailyItems ?? [], lastUpdated: Date(),
            hasPlatformData: existing?.hasPlatformData ?? false
        )
        persistCache()
        return buildSnapshot()
    }

    /// Trigger WKWebView export to fetch usage data.
    func fetchUsageExport() async {
        guard !isExporting else { return }
        isExporting = true
        cookieExpired = false

        do {
            let items = try await exportService.export()
            applyExportedItems(items)
            persistCache()
        } catch let err as ExportError {
            if case .timeout = err { lastErrorMessage = "Export timed out. Try again or import CSV manually." }
            else { lastErrorMessage = err.localizedDescription }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        isExporting = false
    }

    /// Import usage data from a CSV file.
    func importCSV(url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            lastErrorMessage = "Failed to read file."
            return
        }
        let items = UsageCSVParser.parse(csvData: data)
        guard !items.isEmpty else {
            lastErrorMessage = "No usage records found in CSV."
            return
        }
        applyExportedItems(items)
        persistCache()
        lastErrorMessage = nil
    }

    /// Public method for Settings export to apply items directly.
    func importExportedItems(_ items: [ParsedUsageItem]) {
        applyExportedItems(items)
        persistCache()
    }

    private func applyExportedItems(_ items: [ParsedUsageItem]) {
        log.info("Upserting \(items.count, privacy: .public) items into store")
        self.store.upsert(items)

        let dailies = self.store.dailyItems(days: 10)
        cached = CachedData(
            totalBalance: cached?.totalBalance ?? 0, grantedBalance: cached?.grantedBalance ?? 0,
            toppedUpBalance: cached?.toppedUpBalance ?? 0, isAvailable: cached?.isAvailable ?? false,
            todayCost: self.store.todayCost(), monthlyCost: self.store.monthlyCost(),
            totalTokens: self.store.totalTokens, totalCacheHit: self.store.totalCacheHit, totalRequests: self.store.totalRequests,
            modelV4FlashTokens: self.store.flashTokens(), modelV4FlashCost: self.store.flashCost(),
            modelV4FlashCacheHit: self.store.flashCacheHit(), modelV4FlashCacheMiss: self.store.flashCacheMiss(),
            modelV4ProTokens: self.store.proTokens(), modelV4ProCost: self.store.proCost(),
            modelV4ProCacheHit: self.store.proCacheHit(), modelV4ProCacheMiss: self.store.proCacheMiss(),
            dailyItems: dailies, lastUpdated: Date(), hasPlatformData: self.store.hasData
        )
        log.info("Store has \(dailies.count, privacy: .public) daily groups, monthly=¥\(String(format: "%.2f", self.store.monthlyCost()), privacy: .public)")
    }

    // MARK: API

    private func fetchBalance(apiKey: String) async throws -> BalanceResponse {
        guard let network else {
            throw DeepSeekError.networkError("Network capability not available")
        }
        let request = NetworkRequest(
            url: URL(string: "\(apiBase)/user/balance")!,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Accept": "application/json"
            ]
        )
        let (data, http) = try await network.send(request)
        if http.statusCode == 401 { throw DeepSeekError.invalidKey }
        if http.statusCode != 200 { throw DeepSeekError.apiError(http.statusCode, "") }
        return try JSONDecoder().decode(BalanceResponse.self, from: data)
    }

    private func buildSnapshot() -> ModuleSnapshot {
        guard let c = cached else { return ModuleSnapshot(id: manifest.id, title: "DeepSeek", subtitle: "No data", systemImage: manifest.systemImage) }
        var sigs: [StatusSignal] = []
        // "Account Issue" stays as a signal and is also surfaced as health.
        if !c.isAvailable { sigs.append(StatusSignal(id: "ds.unav", title: "Account Issue", message: "Account unavailable.", systemImage: "exclamationmark.triangle", severity: .warning, priority: 90)) }
        if cookieExpired { sigs.append(StatusSignal(id: "ds.cookie", title: "Session Expired", message: "Re-login needed.", systemImage: "person.badge.key", severity: .warning, priority: 80)) }
        return ModuleSnapshot(id: manifest.id, title: String(format: "¥%.2f", c.totalBalance),
            subtitle: c.hasPlatformData ? "Today ¥\(String(format: "%.2f", c.todayCost))" : "Export usage from Settings",
            systemImage: manifest.systemImage, signals: sigs,
            metrics: ["totalBalance": c.totalBalance, "todayCost": c.todayCost, "monthlyCost": c.monthlyCost])
    }

    private func persistCache() {
        guard let c = cached, let data = try? JSONEncoder().encode(c) else { return }
        cache?.saveDomainState(data)
    }

    private func loadState() {
        guard let data = cache?.loadDomainState(),
              let c = try? JSONDecoder().decode(CachedData.self, from: data) else { return }
        cached = c
    }
}
