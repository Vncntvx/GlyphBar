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

// MARK: - Usage Record Store

private struct UsageRecord: Codable {
    var date: String; var model: String
    var totalTokens: Int; var promptTokens: Int; var completionTokens: Int
    var inputCacheHitTokens: Int; var inputCacheMissTokens: Int
    var cost: Double; var requestCount: Int
}

private final class UsageRecordStore {
    private let url: URL
    private var records: [String: UsageRecord] = [:] // key = "date|model"

    init() {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/GlyphBar")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        url = cacheDir.appendingPathComponent("deepseek-usage.json")
        load()
    }

    func upsert(_ items: [ParsedUsageItem]) {
        for item in items {
            let key = "\(item.date)|\(item.model)"
            records[key] = UsageRecord(
                date: item.date, model: item.model,
                totalTokens: item.totalTokens, promptTokens: item.promptTokens,
                completionTokens: item.completionTokens,
                inputCacheHitTokens: item.inputCacheHitTokens,
                inputCacheMissTokens: item.inputCacheMissTokens,
                cost: item.cost, requestCount: item.requestCount
            )
        }
        save()
    }

    func dailyItems(days: Int) -> [CachedData.DailyItem] {
        let all = records.values.sorted { $0.date < $1.date }
        let recent = Array(all.suffix(days))
        var map: [String: (t: Int, c: Double, ft: Int, pt: Int, fc: Double, pc: Double)] = [:]
        for r in recent {
            let isFlash = r.model.contains("flash") || r.model.contains("chat")
            var e = map[r.date] ?? (0, 0, 0, 0, 0, 0)
            e.t += r.totalTokens; e.c += r.cost
            if isFlash { e.ft += r.totalTokens; e.fc += r.cost }
            else { e.pt += r.totalTokens; e.pc += r.cost }
            map[r.date] = e
        }
        return map.map { CachedData.DailyItem(date: $0.key, tokens: $0.value.t, cost: $0.value.c,
            flashTokens: $0.value.ft, proTokens: $0.value.pt, flashCost: $0.value.fc, proCost: $0.value.pc) }
            .sorted { $0.date < $1.date }
    }

    var totalTokens: Int { records.values.reduce(0) { $0 + $1.totalTokens } }
    var totalCacheHit: Int { records.values.reduce(0) { $0 + $1.inputCacheHitTokens } }
    var totalRequests: Int { records.values.reduce(0) { $0 + $1.requestCount } }
    var hasData: Bool { !records.isEmpty }

    func flashTokens() -> Int { records.values.filter { $0.model.contains("flash") || $0.model.contains("chat") }.reduce(0) { $0 + $1.totalTokens } }
    func flashCost() -> Double { records.values.filter { $0.model.contains("flash") || $0.model.contains("chat") }.reduce(0) { $0 + $1.cost } }
    func flashCacheHit() -> Int { records.values.filter { $0.model.contains("flash") || $0.model.contains("chat") }.reduce(0) { $0 + $1.inputCacheHitTokens } }
    func flashCacheMiss() -> Int { records.values.filter { $0.model.contains("flash") || $0.model.contains("chat") }.reduce(0) { $0 + $1.inputCacheMissTokens } }
    func proTokens() -> Int { records.values.filter { $0.model.contains("pro") || $0.model.contains("reasoner") }.reduce(0) { $0 + $1.totalTokens } }
    func proCost() -> Double { records.values.filter { $0.model.contains("pro") || $0.model.contains("reasoner") }.reduce(0) { $0 + $1.cost } }
    func proCacheHit() -> Int { records.values.filter { $0.model.contains("pro") || $0.model.contains("reasoner") }.reduce(0) { $0 + $1.inputCacheHitTokens } }
    func proCacheMiss() -> Int { records.values.filter { $0.model.contains("pro") || $0.model.contains("reasoner") }.reduce(0) { $0 + $1.inputCacheMissTokens } }

    func todayCost() -> Double {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; let today = f.string(from: Date())
        return records.values.filter { $0.date == today }.reduce(0) { $0 + $1.cost }
    }

    func monthlyCost() -> Double {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        let cal = Calendar.current; let today = Date()
        let monthStart = f.string(from: cal.date(from: cal.dateComponents([.year, .month], from: today))!)
        return records.values.filter { $0.date >= monthStart }.reduce(0) { $0 + $1.cost }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([UsageRecord].self, from: data) else { return }
        for r in arr { records["\(r.date)|\(r.model)"] = r }
    }

    private func save() {
        let arr = Array(records.values)
        guard let data = try? JSONEncoder().encode(arr) else { return }
        try? data.write(to: url)
    }
}

private struct CachedData: Codable {
    let totalBalance: Double; let grantedBalance: Double; let toppedUpBalance: Double
    let isAvailable: Bool
    var todayCost: Double; var monthlyCost: Double
    var totalTokens: Int; var totalCacheHit: Int; var totalRequests: Int
    var modelV4FlashTokens: Int; var modelV4FlashCost: Double; var modelV4FlashCacheHit: Int; var modelV4FlashCacheMiss: Int
    var modelV4ProTokens: Int; var modelV4ProCost: Double; var modelV4ProCacheHit: Int; var modelV4ProCacheMiss: Int
    var dailyItems: [DailyItem]; var lastUpdated: Date; var hasPlatformData: Bool
    struct DailyItem: Codable {
        let date: String; var tokens: Int; var cost: Double
        var flashTokens: Int; var proTokens: Int; var flashCost: Double; var proCost: Double
    }
}

// MARK: - Module

@MainActor
final class DeepSeekModule: StatusModule {
    private var cached: CachedData?
    private var lastErrorMessage: String?
    private var platformCookie: String?
    private var cookieExpired = false
    private var isExporting = false

    private let apiBase = "https://api.deepseek.com"
    private let defaults = UserDefaults.standard
    private let exportService = UsageExportService()
    private let store = UsageRecordStore()

    init() { loadState(); platformCookie = defaults.string(forKey: "deepseek.platformCookie") }

    /// Validates an API key by calling the /user/balance endpoint. Throws on failure.
    static func validateApiKey(_ key: String) async throws {
        let apiBase = "https://api.deepseek.com"
        var req = URLRequest(url: URL(string: "\(apiBase)/user/balance")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw DeepSeekError.networkError("Invalid response") }
        if http.statusCode == 401 { throw DeepSeekError.invalidKey }
        if http.statusCode == 403 { throw DeepSeekError.forbidden }
        if http.statusCode == 429 { throw DeepSeekError.rateLimited }
        if http.statusCode != 200 { throw DeepSeekError.apiError(http.statusCode, "") }
    }

    var manifest: ModuleManifest {
        ModuleManifest(id: "deepseek", displayName: "DeepSeek", subtitle: "API balance & usage tracker",
            systemImage: "brain.head.profile", version: "1.2.0", author: "Wenjie Xu",
            capabilities: [.statusItem, .panel, .widgets, .actions, .cachedState, .deepLinks],
            permissions: [], defaultRefreshPolicy: .interval(seconds: 300),
            actions: [ModuleAction(id: "refresh", title: "Refresh", systemImage: "arrow.clockwise", role: .refresh)], widgets: [])
    }

    func refresh(context: ModuleContext) async throws -> ModuleSnapshot {
        lastErrorMessage = nil; cookieExpired = false
        platformCookie = context.secureStore.secret(for: "deepseek.platformCookie")
        let apiKey = context.secureStore.secret(for: "deepseek.apiKey") ?? ""

        let balance = try? await fetchBalance(apiKey: apiKey)
        let totalBal = Double(balance?.balanceInfos.first?.totalBalance ?? "0") ?? 0
        let granted = Double(balance?.balanceInfos.first?.grantedBalance ?? "0") ?? 0
        let topped = Double(balance?.balanceInfos.first?.toppedUpBalance ?? "0") ?? 0

        // If we already have platform data, keep it; export is triggered manually
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

	        // Auto-export usage on refresh when logged in (non-blocking)
	        if !isExporting, let cookie = platformCookie, !cookie.isEmpty {
	            Task { await fetchUsageExport() }
	        }
	        return buildSnapshot()
    }

    /// Trigger WKWebView export to fetch usage data
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

    /// Import usage data from a CSV file
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

    /// Public method for Settings export to apply items directly
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

    func handle(action: ModuleAction, context: ModuleContext) async throws -> ModuleEvent {
        switch action.id {
        case "refresh": return .refreshRequested(manifest.id)
        default: return .none
        }
    }

    func makePanelView(context: ModuleContext, snapshot: ModuleSnapshot?) -> AnyView {
        AnyView(DeepSeekPanel(
            snapshot: snapshot, cached: cached, lastErrorMessage: lastErrorMessage,
            cookieExpired: cookieExpired, isExporting: isExporting,
            hasApiKey: context.secureStore.secret(for: "deepseek.apiKey")?.isEmpty == false,
            hasCookie: platformCookie?.isEmpty == false,
            onSetKey: { context.secureStore.setSecret($0, for: "deepseek.apiKey") },
            onClearKey: { [weak self] in self?.cached = nil; self?.lastErrorMessage = nil; context.secureStore.setSecret(nil, for: "deepseek.apiKey") },
            onRefresh: { [weak self] in Task { guard let self else { return }
                do { let s = try await self.refresh(context: context); context.cacheStore.save(s) }
                catch { self.lastErrorMessage = error.localizedDescription } } },
            onFetchUsage: { [weak self] in Task { await self?.fetchUsageExport() } },
            onImportCSV: { [weak self] in self?.openCSVPanel() }
        ))
    }

    private func openCSVPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .init(filenameExtension: "csv")!, .zip]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            self?.importCSV(url: url)
        }
    }

    // MARK: API

    private func fetchBalance(apiKey: String) async throws -> BalanceResponse {
        var req = URLRequest(url: URL(string: "\(apiBase)/user/balance")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw DeepSeekError.networkError("Invalid") }
        if http.statusCode == 401 { throw DeepSeekError.invalidKey }
        if http.statusCode != 200 { throw DeepSeekError.apiError(http.statusCode, "") }
        return try JSONDecoder().decode(BalanceResponse.self, from: data)
    }

    private func buildSnapshot() -> ModuleSnapshot {
        guard let c = cached else { return ModuleSnapshot(id: manifest.id, title: "DeepSeek", subtitle: "No data", systemImage: manifest.systemImage) }
        var sigs: [StatusSignal] = []
        if !c.isAvailable { sigs.append(StatusSignal(id: "ds.unav", title: "Account Issue", message: "Account unavailable.", systemImage: "exclamationmark.triangle", severity: .warning, priority: 90)) }
        if cookieExpired { sigs.append(StatusSignal(id: "ds.cookie", title: "Session Expired", message: "Re-login needed.", systemImage: "person.badge.key", severity: .warning, priority: 80)) }
        return ModuleSnapshot(id: manifest.id, title: String(format: "¥%.2f", c.totalBalance),
            subtitle: c.hasPlatformData ? "Today ¥\(String(format: "%.2f", c.todayCost))" : "Export usage from Settings",
            systemImage: manifest.systemImage, signals: sigs,
            metrics: ["totalBalance": c.totalBalance, "todayCost": c.todayCost, "monthlyCost": c.monthlyCost])
    }

    private static let cacheKey = "deepseek.cache"
    private func persistCache() { if let c = cached, let d = try? JSONEncoder().encode(c) { defaults.set(d, forKey: Self.cacheKey) } }
    private func loadState() { if let d = defaults.data(forKey: Self.cacheKey), let c = try? JSONDecoder().decode(CachedData.self, from: d) { cached = c } }
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
    var onFetchUsage: () -> Void; var onImportCSV: () -> Void

    @State private var apiKeyInput = ""; @State private var showKeyField = false; @State private var showLoginSheet = false

    var body: some View {
        VStack(spacing: 16) {
            if !hasApiKey || showKeyField { setupView }
            else if let c = cached { connectedView(data: c) }
            else if let err = lastErrorMessage { errorView(message: err) }
            else { GlyphLoadingView().frame(height: 200).onAppear { onRefresh() } }
        }
        .padding(14)
        .sheet(isPresented: $showLoginSheet) { LoginSheet { cookie in
            UserDefaults.standard.set(cookie, forKey: "deepseek.platformCookie"); showLoginSheet = false; onRefresh()
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

    // MARK: Layer 1 - Global Overview

    private func overviewCard(data: CachedData) -> some View {
        GlyphCard {
            HStack(alignment: .top, spacing: 0) {
                // Money side
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

                // Usage side
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

    // MARK: Layer 2 - Model Detail Cards

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
                // Cache hit ratio progress bar
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

    // MARK: Layer 3 - Trend Chart

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

    // Fetch prompt
    private var fetchPromptCard: some View {
        GlyphCard {
            VStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 28)).symbolRenderingMode(.hierarchical).foregroundStyle(.blue)
                Text("Get Usage Data").font(.callout.weight(.semibold))
                Text("Fetch detailed token usage and cost breakdown from DeepSeek platform.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    if isExporting {
                        ProgressView().scaleEffect(0.7); Text("Exporting…").font(.caption).foregroundStyle(.secondary)
                    } else if !hasCookie {
                        Button { showLoginSheet = true } label: { Label("Login First", systemImage: "person.badge.key").frame(width: 120) }.buttonStyle(.borderedProminent).controlSize(.small)
                    } else {
                        Button(action: onFetchUsage) { Label("Fetch Usage", systemImage: "arrow.down.doc").frame(width: 120) }.buttonStyle(.borderedProminent).controlSize(.small)
                        Button(action: onImportCSV) { Label("Import CSV", systemImage: "doc.text").frame(width: 110) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                if let err = lastErrorMessage { Text(err).font(.caption2).foregroundStyle(.red) }
            }.frame(maxWidth: .infinity)
        }
    }

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
