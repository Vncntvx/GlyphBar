import SwiftUI

struct DeepSeekTrendBars: View {
    let items: [CachedData.DailyItem]
    let mode: Int
    let metric: Int

    var body: some View {
        let all = filled10()
        let maxValue = all.map { trendValue($0) }.max() ?? 1
        let today = todayKey()

        GeometryReader { geo in
            let width = max((geo.size.width - CGFloat(all.count - 1) * 4) / CGFloat(all.count), 8)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<all.count, id: \.self) { index in
                    let item = all[index]
                    let value = trendValue(item)
                    let isToday = item.date == today
                    let fill: Color = isToday ? .accentColor : value > 0 ? Color.secondary.opacity(0.45) : Color.primary.opacity(0.06)
                    let height = value > 0 ? max(sqrt(max(value, 0)) / sqrt(max(maxValue, 1)) * 60, 4) : 3.0

                    VStack(spacing: 2) {
                        if value > 0 {
                            Text(metric == 0 ? shortNumber(value) : String(format: "%.2f", value))
                                .font(.system(size: 7, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        RoundedRectangle(cornerRadius: 2)
                            .fill(fill)
                            .frame(width: width, height: height)
                        Text(shortDate(item.date))
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func trendValue(_ item: CachedData.DailyItem) -> Double {
        if metric == 0 {
            switch mode {
            case 1: return Double(item.flashTokens)
            case 2: return Double(item.proTokens)
            default: return Double(item.tokens)
            }
        } else {
            switch mode {
            case 1: return item.flashCost
            case 2: return item.proCost
            default: return item.cost
            }
        }
    }

    private func filled10() -> [CachedData.DailyItem] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let calendar = Calendar.current
        var result = items
        let existing = Set(items.map(\.date))
        var date = calendar.startOfDay(for: .now)

        for _ in 0..<10 {
            let key = formatter.string(from: date)
            if !existing.contains(key) {
                result.append(CachedData.DailyItem(
                    date: key,
                    tokens: 0,
                    cost: 0,
                    flashTokens: 0,
                    proTokens: 0,
                    flashCost: 0,
                    proCost: 0
                ))
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else {
                break
            }
            date = previous
        }

        return Array(result.sorted { $0.date < $1.date }.suffix(10))
    }

    private func todayKey() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: .now)
    }

    private func shortNumber(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    private func shortDate(_ string: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let date = formatter.date(from: string) else { return string }
        return date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
    }
}
