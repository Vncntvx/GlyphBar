import SwiftUI

struct DeepSeekPanel: View {
    let snapshot: ModuleSnapshot?
    let cached: CachedData?
    let lastErrorMessage: String?
    let cookieExpired: Bool
    let isExporting: Bool
    let hasApiKey: Bool
    let hasCookie: Bool
    var onSetKey: (String) -> Void
    var onClearKey: () -> Void
    var onRefresh: () -> Void
    var onFetchUsage: () -> Void
    var onSetCookie: (String) -> Void
    var onImportCSV: () -> Void

    @State private var apiKeyInput = ""
    @State private var showKeyField = false
    @State private var showLoginSheet = false
    @State private var trendMode = 0
    @State private var trendMetric = 0

    var body: some View {
        VStack(spacing: 16) {
            if !hasApiKey || showKeyField {
                setupView
            } else if let cached {
                connectedView(data: cached)
            } else if let lastErrorMessage {
                errorView(message: lastErrorMessage)
            } else {
                GlyphLoadingView().frame(height: 200).task { onRefresh() }
            }
        }
        .padding(14)
        .sheet(isPresented: $showLoginSheet) {
            LoginSheet { cookie in
                onSetCookie(cookie)
                showLoginSheet = false
                onRefresh()
            }
        }
    }

    private var setupView: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 36))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("DeepSeek API Key")
                .font(.title3.weight(.semibold))
            SecureField("sk-...", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            Button("Connect", action: connect)
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
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
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Text("No Usage Data")
                    .font(.callout.weight(.semibold))
                Text("Login and export usage data in Settings -> Modules -> DeepSeek -> Configuration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func overviewCard(data: CachedData) -> some View {
        GlyphCard {
            HStack(alignment: .top, spacing: 0) {
                balanceColumn(data: data)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider().padding(.horizontal, 12)

                usageColumn(data: data)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func balanceColumn(data: CachedData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "creditcard").font(.caption)
                Text("Balance").font(.caption.weight(.semibold))
            }
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
    }

    private func usageColumn(data: CachedData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar").font(.caption)
                Text("Usage").font(.caption.weight(.semibold))
            }
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
    }

    private func modelCards(data: CachedData) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Text("Flash \(Int(ratio(data.modelV4FlashTokens, data.totalTokens)))% · Pro \(Int(ratio(data.modelV4ProTokens, data.totalTokens)))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Total \(fmtTokens(data.totalTokens))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            modelDetailCard(
                name: "V4 Flash",
                icon: "bolt.fill",
                color: .blue,
                tokens: data.modelV4FlashTokens,
                cost: data.modelV4FlashCost,
                cacheHit: data.modelV4FlashCacheHit,
                cacheMiss: data.modelV4FlashCacheMiss
            )
            modelDetailCard(
                name: "V4 Pro",
                icon: "brain.fill",
                color: .purple,
                tokens: data.modelV4ProTokens,
                cost: data.modelV4ProCost,
                cacheHit: data.modelV4ProCacheHit,
                cacheMiss: data.modelV4ProCacheMiss
            )
        }
    }

    private func modelDetailCard(
        name: String,
        icon: String,
        color: Color,
        tokens: Int,
        cost: Double,
        cacheHit: Int,
        cacheMiss: Int
    ) -> some View {
        let input = cacheHit + cacheMiss
        let hitRatio = input > 0 ? Double(cacheHit) / Double(input) : 0
        let percent = Int(hitRatio * 100)
        let unitCost = tokens > 0 ? cost / Double(tokens) * 1_000_000 : 0

        return GlyphCard {
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: icon).foregroundStyle(color)
                        Text(name).font(.callout.weight(.medium))
                    }
                    Spacer()
                    Text(String(format: "¥%.2f", cost))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text("Cache hit").font(.caption2).foregroundStyle(.secondary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.green)
                                .frame(width: max(CGFloat(hitRatio) * geo.size.width, 2), height: 6)
                                .animation(.easeInOut(duration: 0.4), value: hitRatio)
                        }
                    }
                    .frame(height: 6)
                    Text("\(percent)%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
                HStack(spacing: 12) {
                    Text("\(fmtTokens(tokens)) tokens").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if cacheMiss > 0 {
                        Text("miss \(fmtTokens(cacheMiss))").font(.caption2).foregroundStyle(.orange)
                    }
                    Text(String(format: "¥%.4f/M", unitCost)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func trendCard(data: CachedData) -> some View {
        GlyphCard {
            VStack(spacing: 10) {
                HStack {
                    Label("Trend", systemImage: "chart.bar").font(.callout.weight(.semibold))
                    Spacer()
                    Picker("View", selection: $trendMode) {
                        Text("Total").tag(0)
                        Text("Flash").tag(1)
                        Text("Pro").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 130)
                    Picker("Metric", selection: $trendMetric) {
                        Text("Tokens").tag(0)
                        Text("Cost").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 110)
                }

                DeepSeekTrendBars(items: data.dailyItems, mode: trendMode, metric: trendMetric)
                    .frame(height: 72)

                let total7d = data.dailyItems.reduce(0.0) { $0 + (trendMetric == 0 ? Double($1.tokens) : $1.cost) }
                HStack {
                    Spacer()
                    Text("Total: \(trendMetric == 0 ? fmtTokens(Int(total7d)) : String(format: "¥%.2f", total7d))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            Button(action: onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            if let date = cached?.lastUpdated {
                Text("Updated \(rel(date))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.octagon")
                .font(.system(size: 36))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
            Text("Error").font(.title3.weight(.semibold))
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Retry", action: onRefresh).buttonStyle(.borderedProminent)
                Button("Change Key") { showKeyField = true }.buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func connect() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        onSetKey(key)
        apiKeyInput = ""
        showKeyField = false
        onRefresh()
    }

    private func ratio(_ lhs: Int, _ rhs: Int) -> Double {
        rhs > 0 ? Double(lhs) / Double(rhs) * 100 : 0
    }

    private func fmtTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func rel(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
