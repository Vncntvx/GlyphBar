import Foundation
import OSLog

private let deepSeekLog = Logger(subsystem: "com.wenjiexu.GlyphBar", category: "DeepSeek")

extension DeepSeekModule {
    func refreshSnapshot() async throws -> ModuleSnapshot {
        lastErrorMessage = nil
        cookieExpired = false

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

    func applyExportedItems(_ items: [ParsedUsageItem]) {
        deepSeekLog.info("Upserting \(items.count, privacy: .public) items into store")
        store.upsert(items)

        let dailies = store.dailyItems(days: 10)
        cached = CachedData(
            totalBalance: cached?.totalBalance ?? 0, grantedBalance: cached?.grantedBalance ?? 0,
            toppedUpBalance: cached?.toppedUpBalance ?? 0, isAvailable: cached?.isAvailable ?? false,
            todayCost: store.todayCost(), monthlyCost: store.monthlyCost(),
            totalTokens: store.totalTokens, totalCacheHit: store.totalCacheHit, totalRequests: store.totalRequests,
            modelV4FlashTokens: store.flashTokens(), modelV4FlashCost: store.flashCost(),
            modelV4FlashCacheHit: store.flashCacheHit(), modelV4FlashCacheMiss: store.flashCacheMiss(),
            modelV4ProTokens: store.proTokens(), modelV4ProCost: store.proCost(),
            modelV4ProCacheHit: store.proCacheHit(), modelV4ProCacheMiss: store.proCacheMiss(),
            dailyItems: dailies, lastUpdated: Date(), hasPlatformData: store.hasData
        )
        deepSeekLog.info("Store has \(dailies.count, privacy: .public) daily groups, monthly=¥\(String(format: "%.2f", self.store.monthlyCost()), privacy: .public)")
    }

    func buildSnapshot() -> ModuleSnapshot {
        guard let c = cached else {
            return ModuleSnapshot(
                id: manifest.id,
                title: "DeepSeek",
                subtitle: "No data",
                systemImage: manifest.systemImage
            )
        }
        var sigs: [StatusSignal] = []
        if !c.isAvailable {
            sigs.append(StatusSignal(
                id: "ds.unav", title: "Account Issue", message: "Account unavailable.",
                systemImage: "exclamationmark.triangle", severity: .warning, priority: 90
            ))
        }
        if cookieExpired {
            sigs.append(StatusSignal(
                id: "ds.cookie", title: "Session Expired", message: "Re-login needed.",
                systemImage: "person.badge.key", severity: .warning, priority: 80
            ))
        }
        return ModuleSnapshot(
            id: manifest.id,
            title: String(format: "¥%.2f", c.totalBalance),
            subtitle: c.hasPlatformData ? "Today ¥\(String(format: "%.2f", c.todayCost))" : "Export usage from Settings",
            systemImage: manifest.systemImage,
            signals: sigs,
            metrics: ["totalBalance": c.totalBalance, "todayCost": c.todayCost, "monthlyCost": c.monthlyCost]
        )
    }

    func persistCache() {
        guard let c = cached, let data = try? JSONEncoder().encode(c) else { return }
        cache?.saveDomainState(data)
    }

    func loadState() {
        guard let data = cache?.loadDomainState(),
              let c = try? JSONDecoder().decode(CachedData.self, from: data) else { return }
        cached = c
    }
}
