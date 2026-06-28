import Foundation
import SwiftUI
import AppKit

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

// MARK: - Cache

private struct CachedData: Codable {
    let totalBalance: Double; let grantedBalance: Double; let toppedUpBalance: Double
    let isAvailable: Bool
    var dailyCost: Double; var monthlyCost: Double
    var totalTokens: Int; var dailyTokens: Int
    var modelV4FlashTokens: Int; var modelV4FlashCost: Double
    var modelV4ProTokens: Int; var modelV4ProCost: Double
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

    init() { loadState(); platformCookie = defaults.string(forKey: "deepseek.platformCookie") }

    var manifest: ModuleManifest {
        ModuleManifest(id: "deepseek", displayName: "DeepSeek", subtitle: "API balance & usage tracker",
            systemImage: "brain.head.profile", version: "1.2.0", author: "Wenjie Xu",
            capabilities: [.statusItem, .panel, .widgets, .actions, .cachedState, .deepLinks],
            permissions: [], defaultRefreshPolicy: .interval(seconds: 300),
            actions: [ModuleAction(id: "fetchUsage", title: "Fetch Usage", systemImage: "arrow.down.doc"),
                      ModuleAction(id: "refresh", title: "Refresh", systemImage: "arrow.clockwise", role: .refresh),
                      ModuleAction(id: "openPlatform", title: "Dashboard", systemImage: "safari")], widgets: [])
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
            dailyCost: existing?.dailyCost ?? 0, monthlyCost: existing?.monthlyCost ?? 0,
            totalTokens: existing?.totalTokens ?? 0, dailyTokens: existing?.dailyTokens ?? 0,
            modelV4FlashTokens: existing?.modelV4FlashTokens ?? 0, modelV4FlashCost: existing?.modelV4FlashCost ?? 0,
            modelV4ProTokens: existing?.modelV4ProTokens ?? 0, modelV4ProCost: existing?.modelV4ProCost ?? 0,
            dailyItems: existing?.dailyItems ?? [], lastUpdated: Date(),
            hasPlatformData: existing?.hasPlatformData ?? false
        )
        persistCache()
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

    private func applyExportedItems(_ items: [ParsedUsageItem]) {
        let flashItems = items.filter { $0.model == "deepseek-v4-flash" || $0.model == "deepseek-chat" }
        let proItems = items.filter { $0.model == "deepseek-v4-pro" || $0.model == "deepseek-reasoner" }

        let flashTokens = flashItems.reduce(0) { $0 + $1.totalTokens }
        let flashCost = flashItems.reduce(0.0) { $0 + $1.cost }
        let proTokens = proItems.reduce(0) { $0 + $1.totalTokens }
        let proCost = proItems.reduce(0.0) { $0 + $1.cost }
        let totalT = flashTokens + proTokens

        var dailyMap: [String: (t: Int, c: Double, ft: Int, pt: Int, fc: Double, pc: Double)] = [:]
        for item in items {
            let isFlash = item.model == "deepseek-v4-flash" || item.model == "deepseek-chat"
            var e = dailyMap[item.date] ?? (0, 0, 0, 0, 0, 0)
            e.t += item.totalTokens; e.c += item.cost
            if isFlash { e.ft += item.totalTokens; e.fc += item.cost }
            else { e.pt += item.totalTokens; e.pc += item.cost }
            dailyMap[item.date] = e
        }
        let sortedDates = dailyMap.keys.sorted().suffix(7)
        let dailies: [CachedData.DailyItem] = sortedDates.map { d in
            let v = dailyMap[d] ?? (0, 0, 0, 0, 0, 0)
            return CachedData.DailyItem(date: d, tokens: v.t, cost: v.c, flashTokens: v.ft, proTokens: v.pt, flashCost: v.fc, proCost: v.pc)
        }
        let dailyT = items.filter { $0.date == dailies.last?.date }.reduce(0) { $0 + $1.totalTokens }
        let dailyC = dailies.last?.cost ?? 0
        let monthlyC = dailies.reduce(0) { $0 + $1.cost }

        cached = CachedData(
            totalBalance: cached?.totalBalance ?? 0, grantedBalance: cached?.grantedBalance ?? 0,
            toppedUpBalance: cached?.toppedUpBalance ?? 0, isAvailable: cached?.isAvailable ?? false,
            dailyCost: dailyC, monthlyCost: monthlyC,
            totalTokens: totalT, dailyTokens: dailyT,
            modelV4FlashTokens: flashTokens, modelV4FlashCost: flashCost,
            modelV4ProTokens: proTokens, modelV4ProCost: proCost,
            dailyItems: dailies, lastUpdated: Date(), hasPlatformData: true
        )
    }

    func handle(action: ModuleAction, context: ModuleContext) async throws -> ModuleEvent {
        switch action.id {
        case "fetchUsage":
            Task { await fetchUsageExport() }
            return .refreshRequested(manifest.id)
        case "refresh": return .refreshRequested(manifest.id)
        case "openPlatform": NSWorkspace.shared.open(URL(string: "https://platform.deepseek.com/usage")!); return .none
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
            subtitle: c.hasPlatformData ? "Today ¥\(String(format: "%.2f", c.dailyCost))" : "Tap Fetch Usage for stats",
            systemImage: manifest.systemImage, signals: sigs,
            metrics: ["totalBalance": c.totalBalance, "dailyCost": c.dailyCost, "monthlyCost": c.monthlyCost])
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
            if data.hasPlatformData { modelCards(data: data) }
            else { fetchPromptCard }
            trendCard(data: data)
            footerBar
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
                            Text("Month").font(.caption2).foregroundStyle(.secondary)
                            Text("¥\(String(format: "%.2f", data.monthlyCost))").font(.callout.monospacedDigit())
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Today").font(.caption2).foregroundStyle(.secondary)
                            Text("¥\(String(format: "%.2f", data.dailyCost))").font(.callout.monospacedDigit())
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
                            Text("Today").font(.caption2).foregroundStyle(.secondary)
                            Text(fmtTokens(data.dailyTokens)).font(.callout.monospacedDigit())
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Requests").font(.caption2).foregroundStyle(.secondary)
                            Text("\(data.modelV4FlashTokens / max(data.dailyItems.last?.tokens ?? 1, 1))").font(.callout.monospacedDigit())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Layer 2 - Model Detail Cards

    private func modelCards(data: CachedData) -> some View {
        let maxT = max(data.modelV4FlashTokens, data.modelV4ProTokens, 1)
        return VStack(spacing: 8) {
            // Summary label
            HStack(spacing: 16) {
                let totalT = Double(maxT > 0 ? maxT : 1)
                let flashPct = Int(Double(data.modelV4FlashTokens) / totalT * 100)
                let proPct = 100 - flashPct
                Text("Flash \(flashPct)% · Pro \(proPct)%").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Total \(fmtTokens(data.totalTokens))").font(.caption).foregroundStyle(.secondary)
            }

            // Flash card
            modelDetailCard(
                name: "V4 Flash", icon: "bolt.fill", color: .blue,
                tokens: data.modelV4FlashTokens, cost: data.modelV4FlashCost,
                maxTokens: maxT,
                cacheHit: data.modelV4FlashTokens, cacheMiss: 0, completion: 0
            )
            // Pro card
            modelDetailCard(
                name: "V4 Pro", icon: "brain.fill", color: .purple,
                tokens: data.modelV4ProTokens, cost: data.modelV4ProCost,
                maxTokens: maxT,
                cacheHit: data.modelV4ProTokens, cacheMiss: 0, completion: 0
            )
        }
    }

    private func modelDetailCard(name: String, icon: String, color: Color, tokens: Int, cost: Double, maxTokens: Int, cacheHit: Int, cacheMiss: Int, completion: Int) -> some View {
        let pct = maxTokens > 0 ? Int(Double(tokens) / Double(maxTokens) * 100) : 0
        let unitCost = tokens > 0 ? cost / Double(tokens) * 1_000_000 : 0
        return GlyphCard {
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 4) { Image(systemName: icon).foregroundStyle(color); Text(name).font(.callout.weight(.medium)) }
                    Spacer()
                    Text(String(format: "¥%.2f", cost)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    Text("\(pct)%").font(.caption).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(CGFloat(tokens) / CGFloat(maxTokens) * geo.size.width, 2), height: 6)
                            .animation(.easeInOut(duration: 0.4), value: tokens)
                    }
                }.frame(height: 6)

                HStack(spacing: 12) {
                    Text(fmtTokens(tokens) + " tokens").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "¥%.4f/M tokens", unitCost)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

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

                if data.dailyItems.isEmpty {
                    GlyphEmptyStateView(title: "No Trend Data", subtitle: "Usage trend will appear after fetching data.", systemImage: "chart.bar.xaxis").frame(height: 100)
                } else {
                    let filtered = data.dailyItems.filter { day in
                        let v: Double = trendMetric == 0
                            ? (trendMode == 0 ? Double(day.tokens) : trendMode == 1 ? Double(day.flashTokens) : Double(day.proTokens))
                            : (trendMode == 0 ? day.cost : trendMode == 1 ? day.flashCost : day.proCost)
                        return v > 0
                    }
                    if filtered.isEmpty {
                        Text("No data for selected view").font(.caption).foregroundStyle(.secondary).frame(height: 60)
                    } else {
                        let maxV = filtered.map { d -> Double in
                            trendMetric == 0 ? (trendMode == 0 ? Double(d.tokens) : trendMode == 1 ? Double(d.flashTokens) : Double(d.proTokens))
                                           : (trendMode == 0 ? d.cost : trendMode == 1 ? d.flashCost : d.proCost)
                        }.max() ?? 1
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(Array(filtered.enumerated()), id: \.offset) { idx, d in
                                let val: Double = trendMetric == 0
                                    ? (trendMode == 0 ? Double(d.tokens) : trendMode == 1 ? Double(d.flashTokens) : Double(d.proTokens))
                                    : (trendMode == 0 ? d.cost : trendMode == 1 ? d.flashCost : d.proCost)
                                let isLast = d.date == data.dailyItems.last?.date
                                VStack(spacing: 2) {
                                    if val > 0 { Text(trendMetric == 0 ? shortNum(val) : String(format: "%.2f", val)).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary) }
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(isLast ? Color.accentColor : Color.secondary.opacity(0.35))
                                        .frame(width: 20, height: max(CGFloat(val) / CGFloat(maxV) * 70, 2))
                                    Text(shortDate(d.date)).font(.system(size: 7)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                let total7d = data.dailyItems.reduce(0.0) { $0 + (trendMetric == 0 ? Double($1.tokens) : $1.cost) }
                HStack {
                    Spacer()
                    Text("7d: \(trendMetric == 0 ? fmtTokens(Int(total7d)) : String(format: "¥%.2f", total7d))")
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
            if !hasCookie { Button("Login") { showLoginSheet = true }.buttonStyle(.bordered).controlSize(.small) }
            Button(action: { showKeyField = true }) { Label("Change Key", systemImage: "key") }.buttonStyle(.bordered).controlSize(.small)
            Button(action: onImportCSV) { Label("Import CSV", systemImage: "doc.text") }.buttonStyle(.bordered).controlSize(.small)
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
    private func shortDate(_ s: String) -> String { let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; guard let d = f.date(from: s) else { return s }; let df = DateFormatter(); df.dateFormat = "M/d"; return df.string(from: d) }
    private func shortNum(_ v: Double) -> String { v >= 1_000_000 ? String(format: "%.1fM", v/1_000_000) : v >= 1_000 ? String(format: "%.1fK", v/1_000) : String(format: "%.0f", v) }
    private func rel(_ d: Date) -> String { let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f.localizedString(for: d, relativeTo: Date()) }
}
