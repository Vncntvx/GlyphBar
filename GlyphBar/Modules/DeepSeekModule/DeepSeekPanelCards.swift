import SwiftUI

struct DeepSeekOverviewCard: View {
    let data: CachedData

    var body: some View {
        GlyphCard {
            HStack(alignment: .top, spacing: 0) {
                DeepSeekBalanceColumn(data: data)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider().padding(.horizontal, 12)

                DeepSeekUsageColumn(data: data)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct DeepSeekModelCards: View {
    let data: CachedData

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Text("Flash \(Int(DeepSeekFormat.ratio(data.modelV4FlashTokens, data.totalTokens)))% · Pro \(Int(DeepSeekFormat.ratio(data.modelV4ProTokens, data.totalTokens)))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Total \(DeepSeekFormat.tokens(data.totalTokens))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            DeepSeekModelDetailCard(
                name: "V4 Flash",
                icon: "bolt.fill",
                color: .blue,
                tokens: data.modelV4FlashTokens,
                cost: data.modelV4FlashCost,
                cacheHit: data.modelV4FlashCacheHit,
                cacheMiss: data.modelV4FlashCacheMiss
            )
            DeepSeekModelDetailCard(
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
}

struct DeepSeekTrendCard: View {
    let data: CachedData
    @Binding var trendMode: Int
    @Binding var trendMetric: Int

    var body: some View {
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

                let total7d = data.dailyItems.reduce(0.0) {
                    $0 + (trendMetric == 0 ? Double($1.tokens) : $1.cost)
                }
                HStack {
                    Spacer()
                    Text("Total: \(trendMetric == 0 ? DeepSeekFormat.tokens(Int(total7d)) : String(format: "¥%.2f", total7d))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

enum DeepSeekFormat {
    static func tokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    static func ratio(_ lhs: Int, _ rhs: Int) -> Double {
        rhs > 0 ? Double(lhs) / Double(rhs) * 100 : 0
    }
}

private struct DeepSeekBalanceColumn: View {
    let data: CachedData

    var body: some View {
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
}

private struct DeepSeekUsageColumn: View {
    let data: CachedData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar").font(.caption)
                Text("Usage").font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            Text(DeepSeekFormat.tokens(data.totalTokens))
                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cache Hit").font(.caption2).foregroundStyle(.secondary)
                    Text(DeepSeekFormat.tokens(data.totalCacheHit)).font(.callout.monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Requests").font(.caption2).foregroundStyle(.secondary)
                    Text(DeepSeekFormat.tokens(data.totalRequests)).font(.callout.monospacedDigit())
                }
            }
        }
    }
}

private struct DeepSeekModelDetailCard: View {
    let name: String
    let icon: String
    let color: Color
    let tokens: Int
    let cost: Double
    let cacheHit: Int
    let cacheMiss: Int

    var body: some View {
        let input = cacheHit + cacheMiss
        let hitRatio = input > 0 ? Double(cacheHit) / Double(input) : 0
        let percent = Int(hitRatio * 100)
        let unitCost = tokens > 0 ? cost / Double(tokens) * 1_000_000 : 0

        GlyphCard {
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
                    Text("\(DeepSeekFormat.tokens(tokens)) tokens").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if cacheMiss > 0 {
                        Text("miss \(DeepSeekFormat.tokens(cacheMiss))").font(.caption2).foregroundStyle(.orange)
                    }
                    Text(String(format: "¥%.4f/M", unitCost)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
