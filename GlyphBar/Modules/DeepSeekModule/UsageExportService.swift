import Foundation
import WebKit
import OSLog

private let log = Logger(subsystem: "com.wenjiexu.GlyphBar", category: "UsageExport")

@MainActor
final class UsageExportService: NSObject {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[ParsedUsageItem], Error>?
    private var timeoutTask: Task<Void, Never>?
    private var clickAttempts = 0
    private let maxRetries = 3
    private var exportTriggerTime: Date?
    private var isLoggedIn = false

    private let secretStore: ModuleSecretStore?
    private let cache: ModuleCacheNamespace?

    init(
        secretStore: ModuleSecretStore? = nil,
        cache: ModuleCacheNamespace? = nil
    ) {
        self.secretStore = secretStore
        self.cache = cache
        super.init()
    }

    // WKWebView downloads need a writable directory; temp is appropriate for
    // ephemeral export files that are parsed and discarded.
    private var exportsDir: URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "GlyphBarExports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func pruneExports() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: exportsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let sorted = files.sorted { f1, f2 in
            let d1 = (try? f1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let d2 = (try? f2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return d1 > d2
        }
        if sorted.count > 5 {
            for f in sorted[5...] { try? FileManager.default.removeItem(at: f) }
        }
    }

    func export() async throws -> [ParsedUsageItem] {
        guard let cookieStr = secretStore?.secret(for: "deepseek.platformCookie"),
              let tokenPart = cookieStr.components(separatedBy: "; ").first(where: { $0.hasPrefix("authToken=") }) else {
            throw ExportError.notLoggedIn
        }
        let token = String(tokenPart.dropFirst("authToken=".count))
        guard !token.isEmpty else { throw ExportError.notLoggedIn }
        log.info("Export starting, token: \(token.prefix(20), privacy: .public)...")

        cleanup()
        clickAttempts = 0; isLoggedIn = false
        pruneExports()
        try? FileManager.default.contentsOfDirectory(at: exportsDir, includingPropertiesForKeys: nil).forEach {
            try? FileManager.default.removeItem(at: $0)
        }

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()

            let rawToken = secretStore?.secret(for: "deepseek.rawUserToken") ?? ""
            let tokenJS: String
            if !rawToken.isEmpty {
                let escaped = rawToken.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                tokenJS = "localStorage.setItem('userToken', '\(escaped)');"
                log.info("Injecting raw userToken JSON")
            } else {
                tokenJS = "localStorage.setItem('userToken', '\(token)');"
                log.info("Injecting plain token (no rawToken saved)")
            }
            let tokenScript = WKUserScript(source: tokenJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            let interceptScript = WKUserScript(source: UsageExportScripts.interceptJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)

            let uc = WKUserContentController()
            uc.addUserScript(tokenScript)
            uc.addUserScript(interceptScript)
            uc.add(self, name: "usageExport")
            config.userContentController = uc

            let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: config)
            wv.navigationDelegate = self
            wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
            self.webView = wv
            wv.load(URLRequest(url: URL(string: "https://platform.deepseek.com/usage")!))

            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(45))
                guard let self, self.continuation != nil else { return }
                log.info("Export timed out after 45s")
                self.continuation?.resume(throwing: ExportError.timeout)
                self.continuation = nil; self.cleanup()
            }
        }
    }

    private func cleanup() {
        timeoutTask?.cancel(); timeoutTask = nil
        webView?.stopLoading(); webView = nil; continuation = nil
    }

    // MARK: - Click Attempt

    private func attemptClick() {
        guard let wv = webView, continuation != nil, exportTriggerTime == nil else { return }
        guard isLoggedIn else { log.info("Not logged in, skipping click"); return }
        clickAttempts += 1
        log.info("Click \(self.clickAttempts)/\(self.maxRetries)")
        wv.evaluateJavaScript(UsageExportScripts.clickJS) { [weak self] result, error in
            guard let self, self.continuation != nil else { return }
            let msg = (result as? String) ?? "nil"
            log.info("Click: \(msg, privacy: .public)")
            if msg.hasPrefix("react_") || msg.hasPrefix("dom_clicked") || msg.hasPrefix("pending_") {
                self.exportTriggerTime = Date()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    let result = try? await wv.evaluateJavaScript(UsageExportScripts.clickJS)
                    log.info("FollowUp: \(String(describing: result), privacy: .public)")
                }
                self.pollForFile(retries: 16)
            } else if self.clickAttempts < self.maxRetries {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1200))
                    self.attemptClick()
                }
            } else {
                log.info("Failed to find button after \(self.maxRetries) retries")
            }
        }
    }

    private func pollForFile(retries: Int) {
        guard retries > 0, let cont = continuation else { return }
        if let file = newestExportFile(), file.modifiedAt >= (exportTriggerTime ?? Date()).addingTimeInterval(-2) {
            log.info("Download detected: \(file.name, privacy: .public)")
            do {
                let data = try Data(contentsOf: file.url)
                let items = UsageExportFileParser.parse(data: data)
                log.info("Parsed \(items.count, privacy: .public) items")
                cont.resume(returning: items)
                self.continuation = nil; cleanup()
                return
            } catch {
                log.info("Parse error: \(error.localizedDescription)")
            }
        }
        if retries == 14 || retries == 11, let wv = webView {
            log.info("Retry click at poll \(16 - retries)")
            wv.evaluateJavaScript(UsageExportScripts.clickJS, completionHandler: nil)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            self.pollForFile(retries: retries - 1)
        }
    }

    private func newestExportFile() -> (url: URL, name: String, modifiedAt: Date)? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: exportsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        let sorted = files.compactMap { url -> (URL, String, Date)? in
            guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let mod = attrs.contentModificationDate else { return nil }
            return (url, url.lastPathComponent, mod)
        }.sorted { $0.2 > $1.2 }
        return sorted.first
    }

    // MARK: - WKScriptMessageHandler (JS bridge)

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "usageExport", continuation != nil else { return }

        let csvData: Data
        if let dict = message.body as? [String: String], let dataUrl = dict["dataURL"] ?? dict["dataUrl"] {
            log.info("JS bridge: \(dict["filename"] ?? "?", privacy: .public)")
            if let comma = dataUrl.firstIndex(of: ",") {
                csvData = Data(base64Encoded: String(dataUrl[dataUrl.index(after: comma)...])) ?? Data()
            } else { csvData = Data() }
        } else if let base64 = message.body as? String {
            if base64.hasPrefix("data:"), let comma = base64.firstIndex(of: ",") {
                csvData = Data(base64Encoded: String(base64[base64.index(after: comma)...])) ?? Data()
            } else {
                csvData = Data(base64Encoded: base64) ?? Data()
            }
        } else { return }

        guard !csvData.isEmpty else { return }
        let filename = "export-\(Date().timeIntervalSince1970).csv"
        let fileURL = exportsDir.appending(path: filename)
        try? csvData.write(to: fileURL)
        log.info("Saved bridged download: \(filename, privacy: .public) (\(csvData.count) bytes)")
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = webView.url?.absoluteString ?? ""
        log.info("Page loaded: \(url.prefix(80), privacy: .public)")

        if url.contains("sign_in") || url.contains("login") {
            log.info("Login page detected - not logged in")
            isLoggedIn = false
            return
        }
        if url.contains("/usage") || url.contains("platform.deepseek.com") {
            isLoggedIn = true
            log.info("Logged in, scheduling click...")
            Task {
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run { self.attemptClick() }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log.info("Nav fail: \(error.localizedDescription, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation: WKNavigation!, withError error: Error) {
        guard let cont = continuation else { return }
        cont.resume(throwing: error); self.continuation = nil; cleanup()
    }

    // MARK: - WKDownloadDelegate (native download capture)

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        log.info("Navigation became download")
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        log.info("Response became download")
        download.delegate = self
    }

}

// MARK: - WKDownloadDelegate

extension UsageExportService: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let filename = suggestedFilename.isEmpty ? "export-\(Date().timeIntervalSince1970).csv" : suggestedFilename
        let dest = exportsDir.appending(path: filename)
        try? FileManager.default.removeItem(at: dest)
        log.info("Download to: \(filename, privacy: .public)")
        return dest
    }

    func downloadDidFinish(_ download: WKDownload) {
        log.info("WKDownload finished")
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        log.info("WKDownload failed: \(error.localizedDescription)")
    }
}

extension UsageExportService: WKScriptMessageHandler, WKNavigationDelegate {}
