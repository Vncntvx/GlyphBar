import Foundation

// MARK: - Parsed Usage Item

struct ParsedUsageItem {
    let date: String       // yyyy-MM-dd
    let model: String      // deepseek-chat or deepseek-reasoner
    var totalTokens: Int
    var promptTokens: Int
    var completionTokens: Int
    var inputCacheHitTokens: Int
    var inputCacheMissTokens: Int
    var cost: Double       // in yuan
    var requestCount: Int
}

// MARK: - CSV Parser

enum UsageCSVParser {

    /// Parse CSV data from DeepSeek export. Supports both amount-export and general-usage formats.
    static func parse(csvData: Data) -> [ParsedUsageItem] {
        guard let content = String(data: csvData, encoding: .utf8) ?? String(data: csvData, encoding: .ascii) else {
            return []
        }
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else { return [] }

        let header = parseCSVLine(lines[0])

        // Determine format
        if header.contains("type") && header.contains("amount") {
            return parseAmountFormat(lines: lines, header: header)
        } else {
            return parseGeneralFormat(lines: lines, header: header)
        }
    }

    // MARK: - Amount format (utc_date, type, model, amount, ...)

    private static func parseAmountFormat(lines: [String], header: [String]) -> [ParsedUsageItem] {
        let dateIdx = header.firstIndex(where: lowerMatches("utc_date", "date"))
        let typeIdx = header.firstIndex(where: lowerMatches("type"))
        let modelIdx = header.firstIndex(where: lowerMatches("model"))
        let amountIdx = header.firstIndex(where: lowerMatches("amount", "value", "tokens"))

        var groups: [String: [String: Int]] = [:] // date -> model -> aggregated tokens? Not great for this format.

        // For amount format, we need to group by date+model and accumulate by type
        // Key: "date|model" -> type -> amount
        var raw: [String: [String: Int]] = [:]

        for line in Array(lines.dropFirst()) {
            let cols = parseCSVLine(line)
            guard cols.count > max(dateIdx ?? 0, typeIdx ?? 0, modelIdx ?? 0, amountIdx ?? 0) else { continue }
            let date = normalizeDate(dateIdx.map { cols[$0] } ?? "")
            let type = typeIdx.map { cols[$0].lowercased() } ?? ""
            let model = normalizeModel(modelIdx.map { cols[$0] } ?? "")
            let amount = amountIdx.flatMap { Int(cols[$0]) } ?? 0

            guard !date.isEmpty, !model.isEmpty else { continue }
            let key = "\(date)|\(model)"
            raw[key, default: [:]][type, default: 0] += amount
        }

        return raw.map { key, typeMap in
            let parts = key.components(separatedBy: "|")
            let date = parts[0]
            let model = parts.count > 1 ? parts[1] : ""
            let inputCacheMiss = typeMap["inputcachemisstokens"] ?? typeMap["input_cache_miss_tokens"] ?? 0
            let inputCacheHit = typeMap["inputcachehittokens"] ?? typeMap["input_cache_hit_tokens"] ?? 0
            let prompt = inputCacheMiss + inputCacheHit
            let completion = typeMap["outputtokens"] ?? typeMap["completion_tokens"] ?? 0
            let requests = typeMap["requestcount"] ?? typeMap["request_count"] ?? 0
            let total = prompt + completion

            return ParsedUsageItem(
                date: date, model: model,
                totalTokens: total, promptTokens: prompt, completionTokens: completion,
                inputCacheHitTokens: inputCacheHit, inputCacheMissTokens: inputCacheMiss,
                cost: 0, requestCount: requests
            )
        }.sorted { ($0.date, $0.model) < ($1.date, $1.model) }
    }

    // MARK: - General format (date, model, promptTokens, completionTokens, totalTokens, amount, ...)

    private static func parseGeneralFormat(lines: [String], header: [String]) -> [ParsedUsageItem] {
        let dateIdx = header.firstIndex(where: lowerMatches("date", "utc_date"))
        let modelIdx = header.firstIndex(where: lowerMatches("model", "model_name"))
        let promptIdx = header.firstIndex(where: lowerMatches("prompttokens", "prompt_tokens", "input_tokens"))
        let completionIdx = header.firstIndex(where: lowerMatches("completiontokens", "completion_tokens", "output_tokens"))
        let totalIdx = header.firstIndex(where: lowerMatches("totaltokens", "total_tokens", "tokens"))
        let amountIdx = header.firstIndex(where: lowerMatches("amount", "cost", "price"))
        let requestIdx = header.firstIndex(where: lowerMatches("requestcount", "request_count", "requests"))

        return Array(lines.dropFirst()).compactMap { line in
            let cols = parseCSVLine(line)
            guard !cols.isEmpty else { return nil as ParsedUsageItem? }

            let date = normalizeDate(dateIdx.map { cols[$0] } ?? "")
            let model = normalizeModel(modelIdx.map { cols[$0] } ?? "")
            let prompt = promptIdx.flatMap { Int(cols[$0]) } ?? 0
            let completion = completionIdx.flatMap { Int(cols[$0]) } ?? 0
            let total = totalIdx.flatMap { Int(cols[$0]) } ?? (prompt + completion)
            let amount = amountIdx.flatMap { Double(cols[$0]) } ?? 0
            let requests = requestIdx.flatMap { Int(cols[$0]) } ?? 0

            guard !date.isEmpty, !model.isEmpty else { return nil }

            return ParsedUsageItem(
                date: date, model: model,
                totalTokens: total, promptTokens: prompt, completionTokens: completion,
                inputCacheHitTokens: 0, inputCacheMissTokens: 0,
                cost: amount, requestCount: requests
            )
        }
    }

    // MARK: - Helpers

    private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    private static func normalizeDate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let formats = [
            "yyyy-MM-dd", "yyyy/MM/dd", "yyyyMMdd",
            "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")

        // Try custom formats
        for fmt in formats {
            df.dateFormat = fmt
            if let date = df.date(from: trimmed) {
                df.dateFormat = "yyyy-MM-dd"
                return df.string(from: date)
            }
        }

        // Try ISO 8601
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        if let date = iso.date(from: trimmed) {
            df.dateFormat = "yyyy-MM-dd"
            return df.string(from: date)
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) {
            df.dateFormat = "yyyy-MM-dd"
            return df.string(from: date)
        }

        return trimmed
    }

    private static func normalizeModel(_ raw: String) -> String {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("reasoner") || lower.contains("pro") || lower.contains("r1") {
            return "deepseek-reasoner"
        }
        if lower.contains("chat") || lower.contains("flash") || lower.contains("v3") {
            return "deepseek-chat"
        }
        return lower
    }

    private static func lowerMatches(_ candidates: String...) -> (String) -> Bool {
        { s in candidates.map { $0.lowercased() }.contains(s.lowercased()) }
    }
}
