import Foundation
import OSLog

private let usageExportFileParserLog = Logger(
    subsystem: "com.wenjiexu.GlyphBar",
    category: "UsageExport"
)

enum UsageExportFileParser {
    static func parse(data: Data) -> [ParsedUsageItem] {
        if data.starts(with: [0x50, 0x4B]) {
            return unzipAndMerge(data)
        }
        let csv = String(data: data, encoding: .utf8) ?? ""
        usageExportFileParserLog.info("CSV (\(csv.count) chars): \(csv.prefix(200), privacy: .public)")
        return UsageCSVParser.parse(csvData: data)
    }

    private static func unzipAndMerge(_ zipData: Data) -> [ParsedUsageItem] {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "glyph-zip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let zipPath = tmp.appending(path: "e.zip")
            try zipData.write(to: zipPath)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = [
                "-x", "-k",
                zipPath.path(percentEncoded: false),
                tmp.path(percentEncoded: false)
            ]
            try process.run()
            process.waitUntilExit()

            let files = (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
            var allItems: [ParsedUsageItem] = []
            for file in files {
                if let data = try? Data(contentsOf: file) {
                    let items = UsageCSVParser.parse(csvData: data)
                    if !items.isEmpty {
                        usageExportFileParserLog.info("Parsed \(items.count) items from \(file.lastPathComponent, privacy: .public)")
                        allItems.append(contentsOf: items)
                    }
                }
            }
            if !allItems.isEmpty {
                return merge(allItems)
            }
        } catch {}
        return UsageCSVParser.parse(csvData: zipData)
    }

    private static func merge(_ items: [ParsedUsageItem]) -> [ParsedUsageItem] {
        var merged: [String: ParsedUsageItem] = [:]
        for item in items {
            let key = "\(item.date)|\(item.model)"
            if var existing = merged[key] {
                existing.totalTokens = max(existing.totalTokens, item.totalTokens)
                existing.promptTokens = max(existing.promptTokens, item.promptTokens)
                existing.completionTokens = max(existing.completionTokens, item.completionTokens)
                existing.inputCacheHitTokens = max(existing.inputCacheHitTokens, item.inputCacheHitTokens)
                existing.inputCacheMissTokens = max(existing.inputCacheMissTokens, item.inputCacheMissTokens)
                existing.cost = max(existing.cost, item.cost)
                existing.requestCount = max(existing.requestCount, item.requestCount)
                merged[key] = existing
            } else {
                merged[key] = item
            }
        }
        return Array(merged.values).sorted { ($0.date, $0.model) < ($1.date, $1.model) }
    }
}
