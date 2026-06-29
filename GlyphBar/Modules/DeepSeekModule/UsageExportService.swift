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

    // P1.13 bypass #3/#4: read cookie/token via capabilities, not UserDefaults.
    private let secretStore: ModuleSecretStore?
    private let settings: ModuleSettingsNamespace?
    private let cache: ModuleCacheNamespace?

    init(
        secretStore: ModuleSecretStore? = nil,
        settings: ModuleSettingsNamespace? = nil,
        cache: ModuleCacheNamespace? = nil
    ) {
        self.secretStore = secretStore
        self.settings = settings
        self.cache = cache
        super.init()
    }

    // P1.13 bypass #7: use temp directory, not ~/.cache/GlyphBar.
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
        // P1.13 bypass #4: cookie via secretStore capability.
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

            // P1.13 bypass #4: rawUserToken via settings capability.
            let rawToken = settings?["deepseek.rawUserToken"] ?? ""
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
            let interceptScript = WKUserScript(source: Self.interceptJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)

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
        wv.evaluateJavaScript(Self.clickJS) { [weak self] result, error in
            guard let self, self.continuation != nil else { return }
            let msg = (result as? String) ?? "nil"
            log.info("Click: \(msg, privacy: .public)")
            if msg.hasPrefix("react_") || msg.hasPrefix("dom_clicked") || msg.hasPrefix("pending_") {
                self.exportTriggerTime = Date()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    wv.evaluateJavaScript(Self.clickJS) { r, _ in
                        log.info("FollowUp: \(String(describing: r), privacy: .public)")
                    }
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
                let items = parseFile(data: data)
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
            wv.evaluateJavaScript(Self.clickJS, completionHandler: nil)
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

    private func parseFile(data: Data) -> [ParsedUsageItem] {
        if data.starts(with: [0x50, 0x4B]) {
            return unzipAndMerge(data)
        } else {
            let csv = String(data: data, encoding: .utf8) ?? ""
            log.info("CSV (\(csv.count) chars): \(csv.prefix(200), privacy: .public)")
            return UsageCSVParser.parse(csvData: data)
        }
    }

    private func unzipAndMerge(_ zipData: Data) -> [ParsedUsageItem] {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "glyph-zip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let zp = tmp.appending(path: "e.zip")
            try zipData.write(to: zp)
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", zp.path(percentEncoded: false), tmp.path(percentEncoded: false)]; try p.run(); p.waitUntilExit()

            let files = (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
            var allItems: [ParsedUsageItem] = []
            for f in files {
                if let d = try? Data(contentsOf: f) {
                    let items = UsageCSVParser.parse(csvData: d)
                    if !items.isEmpty {
                        log.info("Parsed \(items.count) items from \(f.lastPathComponent, privacy: .public)")
                        allItems.append(contentsOf: items)
                    }
                }
            }
            if !allItems.isEmpty {
                var merged: [String: ParsedUsageItem] = [:]
                for item in allItems {
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
        } catch {}
        return UsageCSVParser.parse(csvData: zipData)
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

    // MARK: - JS Scripts

    private static let interceptJS = """
    (function(){if(window.__gh)return;window.__gh=true;
    const post=(f,d)=>{window.webkit.messageHandlers.usageExport.postMessage({filename:f,dataURL:d})};
    const oc=URL.createObjectURL;URL.createObjectURL=function(b){const r=new FileReader();
    r.onload=()=>post('export.csv',r.result);r.readAsDataURL(b);return oc.call(URL,b)};
    const of=window.fetch;window.fetch=function(...a){return of.apply(this,a).then(r=>{
    const ct=(r.headers.get('content-type')||'').toLowerCase();
    const cd=(r.headers.get('content-disposition')||'').toLowerCase();
    if(ct.includes('zip')||ct.includes('csv')||ct.includes('octet')||ct.includes('excel')||
    cd.includes('attachment')||cd.includes('export')||cd.includes('usage')){
    r.clone().blob().then(b=>{const rr=new FileReader();rr.onload=()=>post('export.csv',rr.result);rr.readAsDataURL(b)})}return r})};
    const OX=window.XMLHttpRequest;window.XMLHttpRequest=function(){const x=new OX();let u='';
    const oo=x.open;x.open=function(m,url,...r){u=url;return oo.call(this,m,url,...r)};
    x.addEventListener('load',function(){const ct=(x.getResponseHeader('content-type')||'').toLowerCase();
    if(ct.includes('csv')||ct.includes('zip')||u.includes('export')||u.includes('download')){
    let b='';const by=new Uint8Array(x.response||x.responseText||'');
    for(let i=0;i<by.length;i++)b+=String.fromCharCode(by[i]);
    post('export.csv','data:text/csv;base64,'+btoa(b))}});return x};
    document.addEventListener('click',function(e){const a=e.target.closest('a');
    if(a&&(a.download||/\\.(csv|zip)/i.test(a.href||''))){e.preventDefault();
    fetch(a.href).then(r=>r.blob()).then(b=>{const rr=new FileReader();
    rr.onload=()=>post(a.download||'export.csv',rr.result);rr.readAsDataURL(b)})}},true)})();
    """

    private static let clickJS = """
    (function(){const btns=document.querySelectorAll('div.ds-button[role="button"]');let t=null;
    btns.forEach(e=>{if((e.textContent||'').trim()==='导出')t=e});
    if(!t){const all=document.querySelectorAll('[role="button"],button,a');
    for(const e of all){if((e.textContent||'').trim().includes('导出')){t=e;break}}}
    if(!t)return'no_button';
    const rk=Object.keys(t).find(k=>k.startsWith('__reactFiber$')||k.startsWith('__reactInternalInstance$'));
    if(rk){const f=t[rk];let c=f;
    for(let i=0;i<15&&c;i++){if(c.memoizedProps&&typeof c.memoizedProps.onClick==='function'){
    c.memoizedProps.onClick({preventDefault:()=>{},stopPropagation:()=>{},nativeEvent:{}});return'react_'+i}
    if(c.pendingProps&&typeof c.pendingProps.onClick==='function'){
    c.pendingProps.onClick({preventDefault:()=>{},stopPropagation:()=>{},nativeEvent:{}});return'pending_'+i}
    c=c.return}}
    t.scrollIntoView({block:'center'});
    ['pointerover','mouseover','pointerenter','mouseenter','pointerdown','mousedown','pointerup','mouseup','click'].forEach(n=>t.dispatchEvent(new MouseEvent(n,{bubbles:true,cancelable:true})));
    if(t.click)t.click();return'dom_clicked'})();
    """
}

// MARK: - WKDownloadDelegate

extension UsageExportService: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL {
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

enum ExportError: LocalizedError {
    case notLoggedIn, authFailed, noData, timeout
    var errorDescription: String? {
        switch self {
        case .notLoggedIn: "Not logged in to DeepSeek platform."
        case .authFailed: "Session expired — please re-login."
        case .noData: "No usage data found in export."
        case .timeout: "Export timed out. Try again."
        }
    }
}
