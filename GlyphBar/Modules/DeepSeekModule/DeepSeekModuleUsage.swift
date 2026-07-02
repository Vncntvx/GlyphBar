import Foundation

extension DeepSeekModule {
    func fetchUsageExport() async {
        guard !isExporting else { return }
        isExporting = true
        cookieExpired = false

        do {
            let items = try await exportService.export()
            applyExportedItems(items)
            persistCache()
        } catch let err as ExportError {
            if case .timeout = err {
                lastErrorMessage = "Export timed out. Try again or import CSV manually."
            } else {
                lastErrorMessage = err.localizedDescription
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        isExporting = false
    }

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

    func importExportedItems(_ items: [ParsedUsageItem]) {
        applyExportedItems(items)
        persistCache()
    }
}
