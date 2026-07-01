import Foundation

struct UsageRecord: Codable {
    var date: String
    var model: String
    var totalTokens: Int
    var promptTokens: Int
    var completionTokens: Int
    var inputCacheHitTokens: Int
    var inputCacheMissTokens: Int
    var cost: Double
    var requestCount: Int
}

@MainActor
final class UsageRecordStore {
    private var records: [String: UsageRecord] = [:]
    private let cache: ModuleCacheNamespace?

    init(cache: ModuleCacheNamespace?) {
        self.cache = cache
        load()
    }

    func upsert(_ items: [ParsedUsageItem]) {
        for item in items {
            let key = "\(item.date)|\(item.model)"
            records[key] = UsageRecord(
                date: item.date,
                model: item.model,
                totalTokens: item.totalTokens,
                promptTokens: item.promptTokens,
                completionTokens: item.completionTokens,
                inputCacheHitTokens: item.inputCacheHitTokens,
                inputCacheMissTokens: item.inputCacheMissTokens,
                cost: item.cost,
                requestCount: item.requestCount
            )
        }
        save()
    }

    func dailyItems(days: Int) -> [CachedData.DailyItem] {
        let all = records.values.sorted { $0.date < $1.date }
        let recent = Array(all.suffix(days))
        var map: [String: (tokens: Int, cost: Double, flashTokens: Int, proTokens: Int, flashCost: Double, proCost: Double)] = [:]

        for record in recent {
            let isFlash = record.model.contains("flash") || record.model.contains("chat")
            var entry = map[record.date] ?? (0, 0, 0, 0, 0, 0)
            entry.tokens += record.totalTokens
            entry.cost += record.cost
            if isFlash {
                entry.flashTokens += record.totalTokens
                entry.flashCost += record.cost
            } else {
                entry.proTokens += record.totalTokens
                entry.proCost += record.cost
            }
            map[record.date] = entry
        }

        return map.map {
            CachedData.DailyItem(
                date: $0.key,
                tokens: $0.value.tokens,
                cost: $0.value.cost,
                flashTokens: $0.value.flashTokens,
                proTokens: $0.value.proTokens,
                flashCost: $0.value.flashCost,
                proCost: $0.value.proCost
            )
        }
        .sorted { $0.date < $1.date }
    }

    var totalTokens: Int {
        records.values.reduce(0) { $0 + $1.totalTokens }
    }

    var totalCacheHit: Int {
        records.values.reduce(0) { $0 + $1.inputCacheHitTokens }
    }

    var totalRequests: Int {
        records.values.reduce(0) { $0 + $1.requestCount }
    }

    var hasData: Bool {
        !records.isEmpty
    }

    func flashTokens() -> Int {
        records.values.filter(isFlash).reduce(0) { $0 + $1.totalTokens }
    }

    func flashCost() -> Double {
        records.values.filter(isFlash).reduce(0) { $0 + $1.cost }
    }

    func flashCacheHit() -> Int {
        records.values.filter(isFlash).reduce(0) { $0 + $1.inputCacheHitTokens }
    }

    func flashCacheMiss() -> Int {
        records.values.filter(isFlash).reduce(0) { $0 + $1.inputCacheMissTokens }
    }

    func proTokens() -> Int {
        records.values.filter(isPro).reduce(0) { $0 + $1.totalTokens }
    }

    func proCost() -> Double {
        records.values.filter(isPro).reduce(0) { $0 + $1.cost }
    }

    func proCacheHit() -> Int {
        records.values.filter(isPro).reduce(0) { $0 + $1.inputCacheHitTokens }
    }

    func proCacheMiss() -> Int {
        records.values.filter(isPro).reduce(0) { $0 + $1.inputCacheMissTokens }
    }

    func todayCost() -> Double {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let today = formatter.string(from: .now)
        return records.values.filter { $0.date == today }.reduce(0) { $0 + $1.cost }
    }

    func monthlyCost() -> Double {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: .now)
        guard let start = calendar.date(from: components) else { return 0 }
        let monthStart = formatter.string(from: start)
        return records.values.filter { $0.date >= monthStart }.reduce(0) { $0 + $1.cost }
    }

    private func load() {
        guard let cache,
              let data = cache.loadDomainState(),
              let records = try? JSONDecoder().decode([UsageRecord].self, from: data)
        else { return }

        for record in records {
            self.records["\(record.date)|\(record.model)"] = record
        }
    }

    private func save() {
        let records = Array(records.values)
        guard let data = try? JSONEncoder().encode(records) else { return }
        cache?.saveDomainState(data)
    }

    private func isFlash(_ record: UsageRecord) -> Bool {
        record.model.contains("flash") || record.model.contains("chat")
    }

    private func isPro(_ record: UsageRecord) -> Bool {
        record.model.contains("pro") || record.model.contains("reasoner")
    }
}

struct CachedData: Codable {
    let totalBalance: Double
    let grantedBalance: Double
    let toppedUpBalance: Double
    let isAvailable: Bool
    var todayCost: Double
    var monthlyCost: Double
    var totalTokens: Int
    var totalCacheHit: Int
    var totalRequests: Int
    var modelV4FlashTokens: Int
    var modelV4FlashCost: Double
    var modelV4FlashCacheHit: Int
    var modelV4FlashCacheMiss: Int
    var modelV4ProTokens: Int
    var modelV4ProCost: Double
    var modelV4ProCacheHit: Int
    var modelV4ProCacheMiss: Int
    var dailyItems: [DailyItem]
    var lastUpdated: Date
    var hasPlatformData: Bool

    struct DailyItem: Codable {
        let date: String
        var tokens: Int
        var cost: Double
        var flashTokens: Int
        var proTokens: Int
        var flashCost: Double
        var proCost: Double
    }
}
