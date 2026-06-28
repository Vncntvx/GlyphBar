import Foundation
import OSLog

private let log = Logger(subsystem: "com.wenjiexu.GlyphBar", category: "UsageExport")

@MainActor
final class UsageExportService {
    private let platformBase = "https://platform.deepseek.com"

    func export() async throws -> [ParsedUsageItem] {
        guard let cookieStr = UserDefaults.standard.string(forKey: "deepseek.platformCookie"),
              let tokenPart = cookieStr.components(separatedBy: "; ").first(where: { $0.hasPrefix("authToken=") }) else {
            log.info("No authToken. Cookie length: \(UserDefaults.standard.string(forKey: "deepseek.platformCookie")?.count ?? 0)")
            throw ExportError.notLoggedIn
        }
        let token = String(tokenPart.dropFirst("authToken=".count))
        log.info("authToken: \(token.prefix(20), privacy: .public)...")
        guard !token.isEmpty else { throw ExportError.notLoggedIn }

        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        let month = cal.component(.month, from: Date())
        
        // Fetch token counts
        let tokenItems = try await fetchAPI(token: token, path: "/api/v0/usage/amount", year: year, month: month, isCost: false)
        // Fetch cost data  
        let costItems = try await fetchAPI(token: token, path: "/api/v0/usage/cost", year: year, month: month, isCost: true)

        // Merge: token items provide token counts, cost items provide yuan costs
        var merged: [String: ParsedUsageItem] = [:]
        for item in tokenItems { merged[item.model] = item }
        for item in costItems {
            if var existing = merged[item.model] {
                existing.cost = item.cost
                merged[item.model] = existing
            } else {
                merged[item.model] = item
            }
        }
        let result = Array(merged.values)
        log.info("Merged \(result.count, privacy: .public) models")
        guard !result.isEmpty else { throw ExportError.noData }
        return result
    }

    private func fetchAPI(token: String, path: String, year: Int, month: Int, isCost: Bool) async throws -> [ParsedUsageItem] {
        var comps = URLComponents(string: "\(platformBase)\(path)")!
        comps.queryItems = [URLQueryItem(name: "year", value: "\(year)"), URLQueryItem(name: "month", value: "\(month)")]
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return [] }
        log.info("\(path): HTTP \(http.statusCode)")
        let body = String(data: data, encoding: .utf8) ?? ""
        if body.contains("\"code\":40003") || http.statusCode == 401 || http.statusCode == 403 { throw ExportError.authFailed }
        guard http.statusCode == 200 else { log.info("Response: \(body.prefix(200), privacy: .public)"); return [] }
        log.info("Success: \(body.prefix(80), privacy: .public)...")
        let items = parsePlatformNested(data: data, isCost: isCost)
        log.info("Parsed \(items.count, privacy: .public) items (\(isCost ? "cost" : "tokens"))")
        return items
    }

    private func parsePlatformNested(data: Data, isCost: Bool) -> [ParsedUsageItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any] else { return [] }
        // biz_data can be {total:[...]} or [{total:[...]}]
        let models: [[String: Any]]
        if let bizObj = dataObj["biz_data"] as? [String: Any],
           let total = bizObj["total"] as? [[String: Any]] {
            models = total
        } else if let bizArr = dataObj["biz_data"] as? [[String: Any]],
                  let first = bizArr.first,
                  let total = first["total"] as? [[String: Any]] {
            models = total
        } else { return [] }
        let today = ISO8601DateFormatter(); today.formatOptions = [.withFullDate]
        let dateStr = today.string(from: Date())
        var items: [ParsedUsageItem] = []
        for modelObj in models {
            guard let modelName = modelObj["model"] as? String,
                  let usages = modelObj["usage"] as? [[String: Any]] else { continue }
            var total = 0, prompt = 0, completion = 0, cacheHit = 0, cacheMiss = 0, requests = 0, cost = 0.0
            for u in usages {
                guard let type = u["type"] as? String, let amountStr = u["amount"] as? String else { continue }
                if isCost {
                    let d = Double(amountStr) ?? 0
                    switch type {
                    case "PROMPT_TOKEN": cost += d
                    case "PROMPT_CACHE_HIT_TOKEN": cost += d
                    case "PROMPT_CACHE_MISS_TOKEN": cost += d
                    case "RESPONSE_TOKEN": cost += d
                    default: break
                    }
                } else {
                    let v = Int(amountStr) ?? 0
                    switch type {
                    case "PROMPT_TOKEN": prompt += v; total += v
                    case "PROMPT_CACHE_HIT_TOKEN": cacheHit += v; total += v
                    case "PROMPT_CACHE_MISS_TOKEN": cacheMiss += v; total += v
                    case "RESPONSE_TOKEN": completion += v; total += v
                    case "REQUEST": requests += v
                    default: break
                    }
                }
            }
            if total > 0 || requests > 0 || cost > 0 {
                items.append(ParsedUsageItem(date: dateStr, model: modelName,
                    totalTokens: total, promptTokens: prompt, completionTokens: completion,
                    inputCacheHitTokens: cacheHit, inputCacheMissTokens: cacheMiss,
                    cost: cost, requestCount: requests))
            }
        }
        return items
    }
}

enum ExportError: LocalizedError {
    case notLoggedIn, authFailed, noData, timeout
    var errorDescription: String? {
        switch self {
        case .notLoggedIn: "Not logged in to DeepSeek platform."
        case .authFailed: "Session expired — please re-login."
        case .noData: "No usage data available."
        case .timeout: "Request timed out."
        }
    }
}
