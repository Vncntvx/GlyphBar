import SwiftUI
import WebKit

struct DeepSeekConfigSection: View {
    let runtime: ModuleRuntime
    let secretStore: ModuleSecretStore
    @State private var keyInput: String = ""
    @State private var isEditingKey = false
    @State private var isValidatingKey = false
    @State private var keyValidationError: String?
    @State private var showLoginSheet = false
    @State private var hasCookie = false
    @State private var hasApiKey = false
    @State private var isExportingUsage = false
    @State private var exportStatus: String?

    private let apiKeyName = "deepseek.apiKey"
    private let cookieKey = "deepseek.platformCookie"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            apiKeyRow
            Divider()
            loginRow
            Divider()
            exportRow
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginSheet(
                onLogin: { cookie in
                    runtime.dispatch(
                        command: .userAction(actionID: "setPlatformCookie", payload: .init(text: cookie)),
                        moduleID: "deepseek"
                    )
                    refreshState()
                },
                onRawToken: { raw in
                    runtime.dispatch(
                        command: .userAction(actionID: "setRawUserToken", payload: .init(text: raw)),
                        moduleID: "deepseek"
                    )
                }
            )
        }
        .onAppear {
            refreshState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshState()
        }
    }

    private var apiKeyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("API Key", systemImage: "key.fill").font(.callout.weight(.medium))
                Spacer()
                if isEditingKey {
                    Button("Cancel") {
                        isEditingKey = false
                        keyValidationError = nil
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(isValidatingKey)
                } else if hasApiKey {
                    Button("Change") {
                        keyInput = secretStore.secret(for: apiKeyName) ?? ""
                        isEditingKey = true
                        keyValidationError = nil
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Button("Remove") {
                        runtime.dispatch(
                            command: .userAction(actionID: "clearApiKey", payload: nil),
                            moduleID: "deepseek"
                        )
                        refreshState()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }

            if isEditingKey {
                HStack {
                    SecureField("sk-...", text: $keyInput)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isValidatingKey)
                    if isValidatingKey {
                        ProgressView().scaleEffect(0.7).frame(width: 20)
                    }
                    Button("Save", action: saveAPIKey)
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .disabled(isValidatingKey || keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error = keyValidationError {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(.caption)
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            } else if hasApiKey {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    Text("Configured").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(.caption)
                    Text("Not configured").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Key") {
                        keyInput = ""
                        isEditingKey = true
                        keyValidationError = nil
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
    }

    private var loginRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Platform Login", systemImage: "person.badge.key").font(.callout.weight(.medium))
                Spacer()
                if hasCookie {
                    Button("Re-login") { showLoginSheet = true }.buttonStyle(.bordered).controlSize(.small)
                    Button("Logout", action: logout)
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            if hasCookie {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    Text("Session active — usage tracking enabled").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "circle").foregroundStyle(.secondary).font(.caption)
                    Text("Login to unlock detailed usage statistics").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Login") { showLoginSheet = true }.buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
        }
    }

    private var exportRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Auto Usage Export", systemImage: "arrow.down.doc").font(.callout.weight(.medium))
                Spacer()
                if isExportingUsage {
                    ProgressView().scaleEffect(0.7)
                    Text("Exporting…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Export") {
                        isExportingUsage = true
                        exportStatus = nil
                        triggerExport()
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(!hasCookie)
                }
            }
            if let exportStatus {
                HStack(spacing: 4) {
                    Image(systemName: exportStatus.hasPrefix("✓") ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(exportStatus.hasPrefix("✓") ? .green : .red).font(.caption)
                    Text(exportStatus).font(.caption).foregroundStyle(.secondary)
                }
            } else if !hasCookie {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary).font(.caption)
                    Text("Login first to export usage data").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func refreshState() {
        hasApiKey = secretStore.secret(for: apiKeyName)?.isEmpty == false
        hasCookie = secretStore.secret(for: cookieKey)?.isEmpty == false
    }

    private func saveAPIKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        validateAndSave(key)
    }

    private func validateAndSave(_ key: String) {
        isValidatingKey = true
        keyValidationError = nil
        Task {
            do {
                try await DeepSeekModule.validateApiKey(key, network: NetworkCapability())
                await MainActor.run {
                    runtime.dispatch(
                        command: .userAction(actionID: "setApiKey", payload: .init(text: key)),
                        moduleID: "deepseek"
                    )
                    isValidatingKey = false
                    isEditingKey = false
                    keyValidationError = nil
                    refreshState()
                }
            } catch {
                await MainActor.run {
                    isValidatingKey = false
                    keyValidationError = error.localizedDescription
                }
            }
        }
    }

    private func logout() {
        runtime.dispatch(
            command: .userAction(actionID: "clearPlatformCookie", payload: nil),
            moduleID: "deepseek"
        )
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            for cookie in cookies {
                WKWebsiteDataStore.default().httpCookieStore.delete(cookie)
            }
        }
        ModuleCacheNamespace(moduleID: "deepseek").clearDomainState()
        hasCookie = false
    }

    private func triggerExport() {
        Task {
            let service = UsageExportService(secretStore: secretStore)
            do {
                let items = try await service.export()
                let data = try JSONEncoder().encode(items)
                await runtime.dispatchAndWait(
                    command: .userAction(actionID: "importUsageItems", payload: .init(data: data)),
                    moduleID: "deepseek"
                )
                await MainActor.run {
                    let directory = FileManager.default.temporaryDirectory.appending(path: "GlyphBarExports")
                    let files = (try? FileManager.default.contentsOfDirectory(
                        atPath: directory.path(percentEncoded: false)
                    ))?.filter { !$0.hasPrefix(".") } ?? []
                    let latest = files.sorted().last ?? "?"
                    exportStatus = "✓ \(items.count) records → \(directory.path(percentEncoded: false))/\(latest)"
                    isExportingUsage = false
                }
            } catch {
                await MainActor.run {
                    exportStatus = "✗ \(error.localizedDescription)"
                    isExportingUsage = false
                }
            }
        }
    }
}
