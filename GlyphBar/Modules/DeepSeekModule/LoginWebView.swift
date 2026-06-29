import SwiftUI
import WebKit
import OSLog

private let log = Logger(subsystem: "com.wenjiexu.GlyphBar", category: "LoginWebView")

struct LoginWebView: NSViewRepresentable {
    let url: URL
    var onCookiesCaptured: (String) -> Void
    var onWebViewCreated: ((WKWebView) -> Void)?
    var onRawTokenCaptured: ((String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(onCookiesCaptured: onCookiesCaptured, onRawTokenCaptured: onRawTokenCaptured) }

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
        let onRawTokenCaptured: ((String) -> Void)?
        private var didCapture = false
        private var rawUserToken: String?

        init(onCookiesCaptured: @escaping (String) -> Void, onRawTokenCaptured: ((String) -> Void)? = nil) {
            self.onCookiesCaptured = onCookiesCaptured
            self.onRawTokenCaptured = onRawTokenCaptured
        }

        /// Manual capture — only triggered when user clicks "Detect Login"
        func captureCookies(from webView: WKWebView) {
            if didCapture {
                log.info("Already captured, resetting for retry")
                didCapture = false
            }
            log.info("Manual capture triggered by user")
            extractAuthData(from: webView)
        }

        // No auto-extraction — user must explicitly click "Detect Login"

        private func extractAuthData(from webView: WKWebView) {
            webView.evaluateJavaScript("JSON.stringify(window.localStorage)") { [weak self] result, error in
                guard let self, !self.didCapture else { return }
                var token: String?
                if let json = result as? String, let data = json.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    log.info("localStorage keys: \(dict.keys.sorted().joined(separator: ", "), privacy: .public)")
                    for key in ["userToken","token","authToken","accessToken","access_token","jwt","auth_token","session_token"] {
                        guard let raw = dict[key] else { continue }
                        // P1.13 bypass #3: store rawUserToken in coordinator, not UserDefaults.
                        if key == "userToken" {
                            self.rawUserToken = raw
                            self.onRawTokenCaptured?(raw)
                        }
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
                log.info("Cookies: \(cookies.count), hasToken: \(token != nil)")
                var parts: [String] = []
                if let t = token { parts.append("authToken=\(t)"); log.info("Captured authToken") }
                else { log.info("No auth token - capturing cookies only") }
                // P1.13 bypass #3/#4: rawUserToken passed via callback, not UserDefaults.standard.
                if let rawToken = self.rawUserToken {
                    parts.append("rawUserToken=\(rawToken)")
                }
                for c in cookies where !c.name.hasPrefix("_ga") && !c.name.hasPrefix("_gid") && !c.name.hasPrefix("_hj") {
                    parts.append("\(c.name)=\(c.value)")
                }
                let cs = parts.joined(separator: "; ")
                log.info("Final: \(cs.count) chars, hasAuthToken: \(token != nil)")
                DispatchQueue.main.async { self.onCookiesCaptured(cs) }
            }
        }
    }
}

struct LoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onLogin: (String) -> Void
    var onRawToken: ((String) -> Void)?
    @State private var showWebView = false
    @State private var webView: WKWebView?
    @State private var isDetecting = false
    @State private var detectionResult: DetectionResult?

    private enum DetectionResult {
        case success(tokenPreview: String)
        case noSession
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("DeepSeek Login", systemImage: "brain.head.profile").font(.headline)
                Spacer()
                if showWebView {
                    if isDetecting {
                        ProgressView().scaleEffect(0.7)
                    } else if case .success = detectionResult {
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    } else {
                        Button("Detect Login") {
                            detectLogin()
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
                Button("Cancel") { dismiss() }.buttonStyle(.bordered).controlSize(.small)
            }.padding(12).background(.thinMaterial)
            Divider()
            if showWebView {
                ZStack(alignment: .bottom) {
                    LoginWebView(url: URL(string: "https://platform.deepseek.com")!,
                        onCookiesCaptured: { cookieString in
                            handleCaptureResult(cookieString)
                        },
                        onWebViewCreated: { wv in webView = wv },
                        onRawTokenCaptured: { raw in onRawToken?(raw) })

                    // Detection status overlay
                    if let result = detectionResult {
                        detectionBanner(result)
                    }
                }
            } else {
                VStack(spacing: 24) {
                    Image(systemName: "safari").font(.system(size: 40)).symbolRenderingMode(.hierarchical).foregroundStyle(.blue)
                    Text("Login to DeepSeek Platform").font(.title3.weight(.semibold))
                    Text("Log in with your credentials on the web page,\nthen click Detect Login to capture your session.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { showWebView = true } label: {
                        Label("Open Login Page", systemImage: "safari").frame(width: 180)
                    }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            }
        }.frame(width: 680, height: 520)
    }

    private func detectLogin() {
        guard let wv = webView, let coord = wv.navigationDelegate as? LoginWebView.Coordinator else { return }
        isDetecting = true
        detectionResult = nil
        coord.captureCookies(from: wv)
        // After 3 seconds, if no result captured, show guidance
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [self] in
            if isDetecting {
                isDetecting = false
                detectionResult = .noSession
            }
        }
    }

    private func handleCaptureResult(_ cookieString: String) {
        isDetecting = false
        let hasAuthToken = cookieString.contains("authToken=")
        if hasAuthToken {
            let preview: String
            if let range = cookieString.range(of: "authToken=") {
                let start = range.upperBound
                let tokenStr = String(cookieString[start...])
                let end = tokenStr.firstIndex(of: ";") ?? tokenStr.endIndex
                let token = String(tokenStr[..<end])
                preview = String(token.prefix(12)) + "..." + String(token.suffix(8))
            } else {
                preview = "detected"
            }
            detectionResult = .success(tokenPreview: preview)
            onLogin(cookieString)
        } else {
            detectionResult = .noSession
        }
    }

    @ViewBuilder
    private func detectionBanner(_ result: DetectionResult) -> some View {
        HStack(spacing: 8) {
            switch result {
            case .success(let preview):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Session detected — \(preview)").font(.caption).foregroundStyle(.primary)
            case .noSession:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text("No session found. Please log in on the page first, then click Detect Login again.")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }
}
