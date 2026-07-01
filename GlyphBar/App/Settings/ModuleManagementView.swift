import SwiftUI
import WebKit

struct ModuleManagementView: View {
    var environment: AppEnvironment
    var runtime: ModuleRuntime
    var settingsStore: AppSettingsStore
    let cacheStore: CacheStore
    @Bindable var navigation: SettingsNavigationState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modules")
                        .font(.title3.weight(.semibold))
                    Text("Enable built-in modules and import local third-party packages.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    environment.importModuleFromPanel()
                } label: {
                    Label("Import Module...", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 12)

            Divider()

            HStack(spacing: 0) {
                List(selection: $navigation.selectedModuleID) {
                    Section("Built-in") {
                        ForEach(runtime.builtInModuleIDs, id: \.self) { moduleID in
                            moduleRow(moduleID: moduleID)
                        }
                    }

                    Section("Third-party") {
                        if runtime.thirdPartyModuleIDs.isEmpty {
                            Text("No third-party modules imported.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(runtime.thirdPartyModuleIDs, id: \.self) { moduleID in
                                moduleRow(moduleID: moduleID)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .frame(width: 250)

                Divider()

                ModuleManagementDetailView(
                    runtime: runtime,
                    settingsStore: settingsStore,
                    cacheStore: cacheStore,
                    environment: environment,
                    selectedModuleID: navigation.selectedModuleID
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if navigation.selectedModuleID == nil {
                navigation.selectedModuleID = runtime.orderedModuleIDs.first
            }
        }
    }

    private func moduleRow(moduleID: ModuleID) -> some View {
        Group {
            if let module = runtime.modules[moduleID] {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(module.manifest.displayName)
                            .lineLimit(1)
                        Text(runtime.record(for: moduleID)?.sourceKind.title ?? "Module")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: module.manifest.systemImage)
                        .symbolRenderingMode(.hierarchical)
                }
                .tag(Optional(moduleID))
            }
        }
    }

}

private struct ModuleManagementDetailView: View {
    var runtime: ModuleRuntime
    var settingsStore: AppSettingsStore
    let cacheStore: CacheStore
    let environment: AppEnvironment
    let selectedModuleID: ModuleID?

    var body: some View {
        Group {
            if let selectedModuleID,
               let module = runtime.modules[selectedModuleID],
               let record = runtime.record(for: selectedModuleID) {
                Form {
                    Section {
                        detailHeader(module: module, record: record)
                    }
                    Section {
                        Picker("Schedule", selection: refreshPolicyBinding(moduleID: module.manifest.id,
                                                                            defaultPolicy: module.manifest.defaultRefreshPolicy)) {
                            Text("Manual").tag(RefreshPolicy.manual)
                            Text("On Launch").tag(RefreshPolicy.onLaunch)
                            Text("Every 5s").tag(RefreshPolicy.interval(seconds: 5))
                            Text("Every 30s").tag(RefreshPolicy.interval(seconds: 30))
                            Text("Every 60s").tag(RefreshPolicy.interval(seconds: 60))
                            Text("Every 30m").tag(RefreshPolicy.interval(seconds: 1800))
                            Text("Every 60m").tag(RefreshPolicy.interval(seconds: 3600))
                            if let custom = customIntervalTag(for: module.manifest.id,
                                                              defaultPolicy: module.manifest.defaultRefreshPolicy) {
                                Text("Custom (\(Int(custom.minimumInterval ?? 0))s)").tag(custom)
                            }
                        }
                    } header: {
                        Text("Refresh")
                    } footer: {
                        Text("Controls how often this module publishes a fresh snapshot.")
                    }
                    if selectedModuleID == "deepseek" {
                        Section {
                            DeepSeekConfigSection(
                                runtime: runtime,
                                secretStore: ModuleSecretStore(moduleID: "deepseek")
                            )
                        } header: {
                            Text("Configuration")
                        } footer: {
                            Text("API key + platform login for full usage tracking.")
                        }
                    }
                    Section {
                        Toggle("Include in Status Bar Rotation", isOn: rotationModuleBinding(module.manifest.id))
                        let candidates = module.statusCandidates()
                        if !candidates.isEmpty && (settingsStore.rotationModuleIDs.contains(module.manifest.id)) {
                            ForEach(candidates) { candidate in
                                Toggle(candidate.text, isOn: rotationItemBinding(moduleID: module.manifest.id, itemID: candidate.id))
                            }
                        }
                    } header: {
                        Text("Status Bar Rotation")
                    } footer: {
                        Text("Choose which information to show when cycling through modules in the status bar.")
                    }
                    Section("Controls") {
                        Toggle("Enabled", isOn: enabledBinding(module.manifest.id))
                        HStack {
                            Button("Move Up") { settingsStore.move(moduleID: module.manifest.id, direction: -1) }
                            Button("Move Down") { settingsStore.move(moduleID: module.manifest.id, direction: 1) }
                            Button("Set Primary") { settingsStore.primaryModuleID = module.manifest.id }
                            Button("Reset Cache", role: .destructive) {
                                settingsStore.resetModuleState(moduleID: module.manifest.id, cacheStore: cacheStore)
                            }
                            if record.canRemove {
                                Button("Remove Module…", role: .destructive) { remove(moduleID: module.manifest.id) }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Section("Metadata") {
                        metadataRow("ID", module.manifest.id)
                        metadataRow("Version", module.manifest.version)
                        metadataRow("Author", module.manifest.author)
                        metadataRow("Type", record.sourceKind.title)
                        metadataRow("Trust", record.trustState.title)
                        if let location = runtime.storageLocation(for: module.manifest.id) {
                            metadataRow("Storage", location.path(percentEncoded: false))
                        }
                    }
                    Section("Capabilities") {
                        if module.manifest.capabilities.isEmpty {
                            Text("None").font(.caption).foregroundStyle(.secondary)
                        } else {
                            FlowLayout(items: module.manifest.capabilities.map(\.rawValue), content: { title in
                                GlyphStatusBadge(severity: .normal, title: title)
                            })
                        }
                    }
                    Section("Permissions") {
                        if module.manifest.permissions.isEmpty {
                            Text("No extra permissions requested.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            FlowLayout(items: module.manifest.permissions.map(\.rawValue), content: { title in
                                GlyphStatusBadge(severity: .warning, title: title)
                            })
                        }
                    }
                    Section("Widgets") {
                        if module.manifest.widgets.isEmpty {
                            Text("No widget descriptor.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(module.manifest.widgets) { widget in
                                Label(widget.title, systemImage: widget.systemImage).font(.callout)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            } else {
                GlyphEmptyStateView(
                    title: "No Module Selected",
                    subtitle: "Choose a module to see details.",
                    systemImage: "square.grid.2x2"
                )
            }
        }
    }

    private func detailHeader(module: any ModuleContract, record: ModuleRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: module.manifest.systemImage)
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(module.manifest.displayName).font(.title2.weight(.semibold))
                Text(module.manifest.subtitle).foregroundStyle(.secondary)
                HStack {
                    GlyphStatusBadge(severity: record.sourceKind == .builtIn ? .normal : .info, title: record.sourceKind.title)
                    GlyphStatusBadge(severity: .info, title: record.trustState.title)
                }
            }
            Spacer()
        }
    }

    private func refreshPolicyBinding(moduleID: ModuleID, defaultPolicy: RefreshPolicy) -> Binding<RefreshPolicy> {
        Binding(
            get: { settingsStore.refreshPolicies[moduleID] ?? defaultPolicy },
            set: { settingsStore.setRefreshPolicy($0, for: moduleID) }
        )
    }

    /// Returns a non-preset interval policy to display as "Custom", if the current
    /// value is an interval not in the preset set {5,30,60,1800,3600}.
    private func customIntervalTag(for moduleID: ModuleID, defaultPolicy: RefreshPolicy) -> RefreshPolicy? {
        let current = settingsStore.refreshPolicies[moduleID] ?? defaultPolicy
        guard case .interval(let seconds) = current else { return nil }
        let presets: Set<TimeInterval> = [5, 30, 60, 1800, 3600]
        return presets.contains(seconds) ? nil : .interval(seconds: seconds)
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary).frame(width: 82, alignment: .leading)
            Text(value).textSelection(.enabled).lineLimit(2)
            Spacer()
        }
        .font(.callout)
    }

    private func enabledBinding(_ moduleID: ModuleID) -> Binding<Bool> {
        Binding(
            get: { settingsStore.isEnabled(moduleID) },
            set: { runtime.setModuleEnabled($0, moduleID: moduleID) }
        )
    }

    private func rotationModuleBinding(_ moduleID: ModuleID) -> Binding<Bool> {
        Binding(
            get: { settingsStore.rotationModuleIDs.contains(moduleID) },
            set: { enabled in
                if enabled {
                    settingsStore.rotationModuleIDs.insert(moduleID)
                } else {
                    settingsStore.rotationModuleIDs.remove(moduleID)
                }
            }
        )
    }

    private func rotationItemBinding(moduleID: ModuleID, itemID: String) -> Binding<Bool> {
        Binding(
            get: {
                settingsStore.rotationItemIDs[moduleID]?.contains(itemID) ?? false
            },
            set: { enabled in
                var items = settingsStore.rotationItemIDs[moduleID] ?? []
                if enabled {
                    items.insert(itemID)
                } else {
                    items.remove(itemID)
                }
                settingsStore.rotationItemIDs[moduleID] = items
            }
        )
    }

    private func remove(moduleID: ModuleID) {
        do {
            try runtime.removeThirdPartyModule(moduleID: moduleID)
        } catch {
            runtime.userNotice = error.localizedDescription
        }
    }
}

// MARK: - DeepSeek Configuration Section

	private struct DeepSeekConfigSection: View {
	    let runtime: ModuleRuntime
	    let secretStore: ModuleSecretStore
	    @State private var keyInput: String = ""
	    @State private var isEditingKey = false
	    @State private var isValidatingKey = false
	    @State private var keyValidationError: String?
	    @State private var showLoginSheet = false
	    @State private var hasCookie = false
	    @State private var hasApiKey = false

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

    private func refreshState() {
        hasApiKey = secretStore.secret(for: apiKeyName)?.isEmpty == false
        hasCookie = secretStore.secret(for: cookieKey)?.isEmpty == false
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

    private func triggerExport() {
        Task {
            let svc = UsageExportService(secretStore: secretStore)
            do {
                let items = try await svc.export()
                let data = try JSONEncoder().encode(items)
                await runtime.dispatchAndWait(
                    command: .userAction(actionID: "importUsageItems", payload: .init(data: data)),
                    moduleID: "deepseek"
                )
                await MainActor.run {
                    let dir = FileManager.default.temporaryDirectory.appending(path: "GlyphBarExports")
                    let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)))?.filter { !$0.hasPrefix(".") } ?? []
                    let latest = files.sorted().last ?? "?"
                    exportStatus = "✓ \(items.count) records → \(dir.path(percentEncoded: false))/\(latest)"
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

    // MARK: API Key

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
                    Button("Change") { keyInput = secretStore.secret(for: apiKeyName) ?? ""; isEditingKey = true; keyValidationError = nil }
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
                    Button("Save") {
                        let k = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !k.isEmpty else { return }
                        validateAndSave(k)
                    }
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
                    Button("Add Key") { keyInput = ""; isEditingKey = true; keyValidationError = nil }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
    }

    // MARK: Platform Login

    private var loginRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Platform Login", systemImage: "person.badge.key").font(.callout.weight(.medium))
                Spacer()
                if hasCookie {
                    Button("Re-login") { showLoginSheet = true }.buttonStyle(.bordered).controlSize(.small)
                    Button("Logout") {
                        // Clear cookie from secure store (Keychain-backed).
                        runtime.dispatch(
                            command: .userAction(actionID: "clearPlatformCookie", payload: nil),
                            moduleID: "deepseek"
                        )
                        // Clear WKWebView cookies so next login starts fresh.
                        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                            for c in cookies {
                                WKWebsiteDataStore.default().httpCookieStore.delete(c)
                            }
                        }
                        // Clear cached platform usage data via the module's cache namespace.
                        let cache = ModuleCacheNamespace(moduleID: "deepseek")
                        cache.clearDomainState()
                        hasCookie = false
                    }
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

    // MARK: Export

    @State private var isExportingUsage = false
    @State private var exportStatus: String?

    private var exportRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Auto Usage Export", systemImage: "arrow.down.doc").font(.callout.weight(.medium))
                Spacer()
                if isExportingUsage {
                    ProgressView().scaleEffect(0.7)
                    Text("Exporting…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Export") { isExportingUsage = true; exportStatus = nil; triggerExport() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .disabled(!hasCookie)
                }
            }
            if let s = exportStatus {
                HStack(spacing: 4) {
                    Image(systemName: s.hasPrefix("✓") ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(s.hasPrefix("✓") ? .green : .red).font(.caption)
                    Text(s).font(.caption).foregroundStyle(.secondary)
                }
            } else if !hasCookie {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary).font(.caption)
                    Text("Login first to export usage data").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }


}
private struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(items), id: \.self) { item in
                content(item)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
