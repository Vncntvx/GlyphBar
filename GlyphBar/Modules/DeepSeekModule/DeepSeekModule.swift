import Foundation
import SwiftUI
import AppKit
import OSLog

private let log = Logger(subsystem: "com.wenjiexu.GlyphBar", category: "DeepSeek")

// MARK: - API Models

private struct BalanceInfo: Codable {
    let currency: String
    let totalBalance: String; let grantedBalance: String; let toppedUpBalance: String
    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance", grantedBalance = "granted_balance", toppedUpBalance = "topped_up_balance"
    }
}
private struct BalanceResponse: Codable {
    let isAvailable: Bool; let balanceInfos: [BalanceInfo]
    enum CodingKeys: String, CodingKey { case isAvailable = "is_available", balanceInfos = "balance_infos" }
}

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

private enum DeepSeekError: LocalizedError {
    case missingKey, invalidKey, forbidden, rateLimited, networkError(String), apiError(Int, String)
    var errorDescription: String? {
        switch self { case .missingKey: "API key not configured"; case .invalidKey: "Invalid API key (401)"; case .forbidden: "Access denied (403)"; case .rateLimited: "Rate limited (429)"; case .networkError(let m): "Network: \(m)"; case .apiError(let c, _): "API error (\(c))" }
    }
}

// MARK: - Panel

private struct DeepSeekPanel: View {
    let snapshot: ModuleSnapshot?; let cached: CachedData?; let lastErrorMessage: String?
    let cookieExpired: Bool; let isExporting: Bool; let hasApiKey: Bool; let hasCookie: Bool
    var onSetKey: (String) -> Void; var onClearKey: () -> Void; var onRefresh: () -> Void
    var onFetchUsage: () -> Void; var onSetCookie: (String) -> Void; var onImportCSV: () -> Void

    @State private var apiKeyInput = ""; @State private var showKeyField = false; @State private var showLoginSheet = false

    var body: some View {
        VStack(spacing: 16) {
            if !hasApiKey || showKeyField { setupView }
            else if let c = cached { connectedView(data: c) }
            else if let err = lastErrorMessage { errorView(message: err) }
            else { GlyphLoadingView().frame(height: 200).task { onRefresh() } }
        }
        .padding(14)
        .sheet(isPresented: $showLoginSheet) { LoginSheet { cookie in
            onSetCookie(cookie)
            showLoginSheet = false
            onRefresh()
        }}
    }

    private var setupView: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill").font(.system(size: 36)).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
            Text("DeepSeek API Key").font(.title3.weight(.semibold))
            SecureField("sk-...", text: $apiKeyInput).textFieldStyle(.roundedBorder).frame(width: 280)
            Button("Connect") { let k = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines); guard !k.isEmpty else { return }; onSetKey(k); apiKeyInput = ""; showKeyField = false; onRefresh() }
                .buttonStyle(.borderedProminent).disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.frame(maxWidth: .infinity).padding(.vertical, 20)
    }

    private func connectedView(data: CachedData) -> some View {
        VStack(spacing: 12) {
            overviewCard(data: data)
            if data.hasPlatformData {
                modelCards(data: data)
                trendCard(data: data)
            } else {
                noDataPrompt
            }
            footerBar
        }
    }

    private var noDataPrompt: some View {
        GlyphCard {
            VStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 28)).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
                Text("No Usage Data").font(.callout.weight(.semibold))
                Text("Login and export usage data in Settings → Modules → DeepSeek → Configuration.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
    }

    private func overviewCard(data: CachedData) -> some View {
        GlyphCard {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) { Image(systemName: "creditcard").font(.caption); Text("Balance").font(.caption.weight(.semibold)) }
                        .foregroundStyle(.secondary)
                    Text(String(format: "¥%.2f", data.totalBalance))
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("This Month").font(.caption2).foregroundStyle(.secondary)
                            Text("¥\(String(format: "%.2f", data.monthlyCost))").font(.callout.monospacedDigit())
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Today").font(.caption2).foregroundStyle(.secondary)
                            Text("¥\(String(format: "%.2f", data.todayCost))").font(.callout.monospacedDigit())
                        }
                    }
                    if !data.isAvailable {
                        GlyphStatusBadge(severity: .critical, title: "Unavailable")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) { Image(systemName: "chart.bar").font(.caption); Text("Usage").font(.caption.weight(.semibold)) }
                        .foregroundStyle(.secondary)
                    Text(fmtTokens(data.totalTokens))
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cache Hit").font(.caption2).foregroundStyle(.secondary)
                            Text(fmtTokens(data.totalCacheHit)).font(.callout.monospacedDigit())
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Requests").font(.caption2).foregroundStyle(.secondary)
                            Text(fmtTokens(data.totalRequests)).font(.callout.monospacedDigit())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func modelCards(data: CachedData) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Text("Flash \(Int(ratio(data.modelV4FlashTokens, data.totalTokens)))% · Pro \(Int(ratio(data.modelV4ProTokens, data.totalTokens)))%").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Total \(fmtTokens(data.totalTokens))").font(.caption).foregroundStyle(.secondary)
            }
            modelDetailCard(name: "V4 Flash", icon: "bolt.fill", color: .blue,
                tokens: data.modelV4FlashTokens, cost: data.modelV4FlashCost,
                cacheHit: data.modelV4FlashCacheHit, cacheMiss: data.modelV4FlashCacheMiss)
            modelDetailCard(name: "V4 Pro", icon: "brain.fill", color: .purple,
                tokens: data.modelV4ProTokens, cost: data.modelV4ProCost,
                cacheHit: data.modelV4ProCacheHit, cacheMiss: data.modelV4ProCacheMiss)
        }
    }

    private func modelDetailCard(name: String, icon: String, color: Color, tokens: Int, cost: Double, cacheHit: Int, cacheMiss: Int) -> some View {
        let input = cacheHit + cacheMiss
        let hitRatio = input > 0 ? Double(cacheHit) / Double(input) : 0
        let pct = Int(hitRatio * 100)
        let unitCost = tokens > 0 ? cost / Double(tokens) * 1_000_000 : 0
        return GlyphCard {
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 4) { Image(systemName: icon).foregroundStyle(color); Text(name).font(.callout.weight(.medium)) }
                    Spacer()
                    Text(String(format: "¥%.2f", cost)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text("Cache hit").font(.caption2).foregroundStyle(.secondary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: [.green, .green.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(CGFloat(hitRatio) * geo.size.width, 2), height: 6)
                                .animation(.easeInOut(duration: 0.4), value: hitRatio)
                        }
                    }.frame(height: 6)
                    Text("\(pct)%").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                }
                HStack(spacing: 12) {
                    Text(fmtTokens(tokens) + " tokens").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if cacheMiss > 0 { Text("miss \(fmtTokens(cacheMiss))").font(.caption2).foregroundStyle(.orange) }
                    Text(String(format: "¥%.4f/M", unitCost)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func ratio(_ a: Int, _ b: Int) -> Double { b > 0 ? Double(a) / Double(b) * 100 : 0 }

    private func trendCard(data: CachedData) -> some View {
        GlyphCard {
            VStack(spacing: 10) {
                HStack {
                    Label("Trend", systemImage: "chart.bar").font(.callout.weight(.semibold))
                    Spacer()
                    Picker("View", selection: $trendMode) { Text("Total").tag(0); Text("Flash").tag(1); Text("Pro").tag(2) }.pickerStyle(.segmented).controlSize(.small).frame(width: 130)
                    Picker("Metric", selection: $trendMetric) { Text("Tokens").tag(0); Text("Cost").tag(1) }.pickerStyle(.segmented).controlSize(.small).frame(width: 110)
                }

                TrendBars(items: data.dailyItems, mode: trendMode, metric: trendMetric)
                    .frame(height: 72)

                let total7d = data.dailyItems.reduce(0.0) { $0 + (trendMetric == 0 ? Double($1.tokens) : $1.cost) }
                HStack {
                    Spacer()
                    Text("Total: \(trendMetric == 0 ? fmtTokens(Int(total7d)) : String(format: "¥%.2f", total7d))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    @State private var trendMode = 0
    @State private var trendMetric = 0

    private var footerBar: some View {
        HStack(spacing: 12) {
            Button(action: onRefresh) { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(.bordered).controlSize(.small)
            Spacer(); if let d = cached?.lastUpdated { Text("Updated \(rel(d))").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.octagon").font(.system(size: 36)).symbolRenderingMode(.hierarchical).foregroundStyle(.red)
            Text("Error").font(.title3.weight(.semibold)); Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 12) { Button("Retry", action: onRefresh).buttonStyle(.borderedProminent); Button("Change Key") { showKeyField = true }.buttonStyle(.bordered) }
        }.frame(maxWidth: .infinity).padding(.vertical, 20)
    }

    private func fmtTokens(_ t: Int) -> String { t >= 1_000_000 ? String(format: "%.1fM", Double(t)/1_000_000) : t >= 1_000 ? String(format: "%.1fK", Double(t)/1_000) : "\(t)" }
    private func rel(_ d: Date) -> String { let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f.localizedString(for: d, relativeTo: Date()) }
}

private func shortNum(_ v: Double) -> String { v >= 1_000_000 ? String(format: "%.1fM", v/1_000_000) : v >= 1_000 ? String(format: "%.1fK", v/1_000) : String(format: "%.0f", v) }
private func shortDate(_ s: String) -> String { let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; guard let d = f.date(from: s) else { return s }; let df = DateFormatter(); df.dateFormat = "M/d"; return df.string(from: d) }

private struct TrendBars: View {
    let items: [CachedData.DailyItem]; let mode: Int; let metric: Int

    private func tv(_ d: CachedData.DailyItem) -> Double {
        if metric == 0 {
            switch mode { case 1: return Double(d.flashTokens); case 2: return Double(d.proTokens); default: return Double(d.tokens) }
        } else {
            switch mode { case 1: return d.flashCost; case 2: return d.proCost; default: return d.cost }
        }
    }

    private func filled10() -> [CachedData.DailyItem] {
        let fmt = ISO8601DateFormatter(); fmt.formatOptions = [.withFullDate]; let cal = Calendar.current
        var r = items; let ex = Set(items.map(\.date)); var d = cal.startOfDay(for: Date())
        for _ in 0..<10 {
            let ds = fmt.string(from: d)
            if !ex.contains(ds) { r.append(CachedData.DailyItem(date: ds, tokens: 0, cost: 0, flashTokens: 0, proTokens: 0, flashCost: 0, proCost: 0)) }
            d = cal.date(byAdding: .day, value: -1, to: d)!
        }
        return r.sorted { $0.date < $1.date }.suffix(10)
    }

    private func todayKey() -> String { let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f.string(from: Date()) }

    var body: some View {
        let all = filled10()
        let maxV = all.map { tv($0) }.max() ?? 1
        let today = todayKey()
        GeometryReader { geo in
            let w = max((geo.size.width - CGFloat(all.count - 1) * 4) / CGFloat(all.count), 8)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<all.count, id: \.self) { idx in
                    let d = all[idx]
                    let val = tv(d)
                    let isToday = d.date == today
                    let fill: Color = isToday ? .accentColor : val > 0 ? Color.secondary.opacity(0.45) : Color.primary.opacity(0.06)
                    let h = val > 0 ? max(sqrt(max(val, 0)) / sqrt(max(maxV, 1)) * 60, 4) : 3.0
                    VStack(spacing: 2) {
                        if val > 0 {
                            Text(metric == 0 ? shortNum(val) : String(format: "%.2f", val))
                                .font(.system(size: 7, weight: .medium)).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: w, height: h)
                        Text(shortDate(d.date)).font(.system(size: 6)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
