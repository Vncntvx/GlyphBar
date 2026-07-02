import SwiftUI

struct DeepSeekPanel: View {
    let snapshot: ModuleSnapshot?
    let cached: CachedData?
    let lastErrorMessage: String?
    let cookieExpired: Bool
    let isExporting: Bool
    let hasApiKey: Bool
    let hasCookie: Bool
    var onSetKey: (String) -> Void
    var onClearKey: () -> Void
    var onRefresh: () -> Void
    var onFetchUsage: () -> Void
    var onSetCookie: (String) -> Void
    var onImportCSV: () -> Void

    @State private var apiKeyInput = ""
    @State private var showKeyField = false
    @State private var showLoginSheet = false
    @State private var trendMode = 0
    @State private var trendMetric = 0

    var body: some View {
        VStack(spacing: 16) {
            if !hasApiKey || showKeyField {
                setupView
            } else if let cached {
                connectedView(data: cached)
            } else if let lastErrorMessage {
                errorView(message: lastErrorMessage)
            } else {
                GlyphLoadingView().frame(height: 200).task { onRefresh() }
            }
        }
        .padding(14)
        .sheet(isPresented: $showLoginSheet) {
            LoginSheet { cookie in
                onSetCookie(cookie)
                showLoginSheet = false
                onRefresh()
            }
        }
    }

    private var setupView: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 36))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("DeepSeek API Key")
                .font(.title3.weight(.semibold))
            SecureField("sk-...", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            Button("Connect", action: connect)
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func connectedView(data: CachedData) -> some View {
        VStack(spacing: 12) {
            DeepSeekOverviewCard(data: data)
            if data.hasPlatformData {
                DeepSeekModelCards(data: data)
                DeepSeekTrendCard(data: data, trendMode: $trendMode, trendMetric: $trendMetric)
            } else {
                noDataPrompt
            }
            footerBar
        }
    }

    private var noDataPrompt: some View {
        GlyphCard {
            VStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Text("No Usage Data")
                    .font(.callout.weight(.semibold))
                Text("Login and export usage data in Settings -> Modules -> DeepSeek -> Configuration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            Button(action: onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            if let date = cached?.lastUpdated {
                Text("Updated \(DeepSeekFormat.relative(date))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.octagon")
                .font(.system(size: 36))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
            Text("Error").font(.title3.weight(.semibold))
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Retry", action: onRefresh).buttonStyle(.borderedProminent)
                Button("Change Key") { showKeyField = true }.buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func connect() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        onSetKey(key)
        apiKeyInput = ""
        showKeyField = false
        onRefresh()
    }

}
