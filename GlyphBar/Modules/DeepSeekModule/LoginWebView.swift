import SwiftUI
import WebKit
import OSLog

private let log = Logger(subsystem: "com.wenjiexu.GlyphBar", category: "LoginWebView")

struct LoginWebView: NSViewRepresentable {
    let url: URL
    var onCookiesCaptured: (String) -> Void
    var onWebViewCreated: ((WKWebView) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(onCookiesCaptured: onCookiesCaptured) }

    func makeNSView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration(); c.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: c)
        wv.navigationDelegate = context.coordinator
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"
        DispatchQueue.main.async { self.onWebViewCreated?(wv) }
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let onCookiesCaptured: (String) -> Void
        private var didCapture = false

        init(onCookiesCaptured: @escaping (String) -> Void) { self.onCookiesCaptured = onCookiesCaptured }

        func captureCookies(from webView: WKWebView) {
            guard !didCapture else { return }
            log.info("Manual capture triggered")
            extractAuthData(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            log.info("didFinish")
            guard !didCapture else { return }
            for delay in [2.0, 5.0, 10.0, 20.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak webView] in
                    guard let self, let wv = webView, !self.didCapture else { return }
                    log.info("Auto-extract at +\(delay)s")
                    self.extractAuthData(from: wv)
                }
            }
        }

        private func extractAuthData(from webView: WKWebView) {
            webView.evaluateJavaScript("JSON.stringify(window.localStorage)") { [weak self] result, error in
                guard let self, !self.didCapture else { return }
                var token: String?
                if let json = result as? String, let data = json.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    log.info("localStorage keys: \(dict.keys.sorted().joined(separator: ", "), privacy: .public)")
                    for key in ["userToken","token","authToken","accessToken","access_token","jwt","auth_token","session_token"] {
                        guard let raw = dict[key] else { continue }
                        // Try nested JSON {value:"..."}
                        if let vd = raw.data(using: .utf8),
                           let vDict = try? JSONSerialization.jsonObject(with: vd) as? [String: String],
                           let inner = vDict["value"] ?? vDict["token"] ?? vDict["access_token"] {
                            token = inner
                            log.info("Found token via \(key).value: \(inner.prefix(30), privacy: .public)...")
                        } else if raw.count > 20 {
                            token = raw
                            log.info("Found token via \(key) (plain): \(raw.prefix(30), privacy: .public)...")
                        }
                        if token != nil { break }
                    }
                    if token == nil { log.info("No known token key. Keys: \(dict.keys.sorted().joined(separator: ", "), privacy: .public)") }
                }
                webView.evaluateJavaScript("JSON.stringify(window.sessionStorage)") { [weak self] result2, _ in
                    guard let self, !self.didCapture else { return }
                    if token == nil, let json2 = result2 as? String, let data2 = json2.data(using: .utf8),
                       let dict2 = try? JSONSerialization.jsonObject(with: data2) as? [String: String] {
                        token = dict2["userToken"] ?? dict2["token"] ?? dict2["authToken"]
                        if let t = token { log.info("Found token in sessionStorage: \(t.prefix(30), privacy: .public)...") }
                    }
                    self.finalizeCapture(token: token, webView: webView)
                }
            }
        }

        private func finalizeCapture(token: String?, webView: WKWebView) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.didCapture else { return }
                self.didCapture = true
                log.info("Cookies: \(cookies.count)")
                var parts: [String] = []
                if let t = token { parts.append("authToken=\(t)"); log.info("Captured authToken") }
                else { log.info("No auth token - cookies only") }
                for c in cookies where !c.name.hasPrefix("_ga") && !c.name.hasPrefix("_gid") && !c.name.hasPrefix("_hj") {
                    parts.append("\(c.name)=\(c.value)")
                }
                let cs = parts.joined(separator: "; ")
                log.info("Final: \(cs.count) chars")
                DispatchQueue.main.async { self.onCookiesCaptured(cs) }
            }
        }
    }
}

struct LoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onLogin: (String) -> Void
    @State private var showWebView = false
    @State private var webView: WKWebView?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("DeepSeek Login", systemImage: "brain.head.profile").font(.headline)
                Spacer()
                if showWebView {
                    Button("Detect Login") {
                        if let wv = webView, let coord = wv.navigationDelegate as? LoginWebView.Coordinator {
                            coord.captureCookies(from: wv)
                        }
                    }.buttonStyle(.borderedProminent).controlSize(.small)
                }
                Button("Cancel") { dismiss() }.buttonStyle(.bordered).controlSize(.small)
            }.padding(12).background(.thinMaterial)
            Divider()
            if showWebView {
                LoginWebView(url: URL(string: "https://platform.deepseek.com")!,
                    onCookiesCaptured: { c in onLogin(c); dismiss() },
                    onWebViewCreated: { wv in webView = wv })
            } else {
                VStack(spacing: 24) {
                    Image(systemName: "safari").font(.system(size: 40)).symbolRenderingMode(.hierarchical).foregroundStyle(.blue)
                    Text("Login to DeepSeek Platform").font(.title3.weight(.semibold))
                    Text("After logging in, click Detect Login.").font(.callout).foregroundStyle(.secondary)
                    Button { showWebView = true } label: {
                        Label("Open Login Page", systemImage: "safari").frame(width: 180)
                    }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            }
        }.frame(width: 680, height: 520)
    }
}
