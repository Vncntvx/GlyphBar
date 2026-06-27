import SwiftUI

struct ModuleManagementView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var runtime: ModuleRuntime
    @ObservedObject var settingsStore: AppSettingsStore
    let cacheStore: CacheStore
    @ObservedObject var navigation: SettingsNavigationState

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
                List(selection: selectedModuleBinding) {
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
                .frame(width: 250)

                Divider()

                ModuleManagementDetailView(
                    runtime: runtime,
                    settingsStore: settingsStore,
                    cacheStore: cacheStore,
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

    private var selectedModuleBinding: Binding<ModuleID?> {
        Binding(
            get: { navigation.selectedModuleID },
            set: { navigation.selectedModuleID = $0 }
        )
    }
}

private struct ModuleManagementDetailView: View {
    @ObservedObject var runtime: ModuleRuntime
    @ObservedObject var settingsStore: AppSettingsStore
    let cacheStore: CacheStore
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
                            metadataRow("Storage", location.path)
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

    private func detailHeader(module: any StatusModule, record: ModuleRecord) -> some View {
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
            set: { settingsStore.setEnabled($0, moduleID: moduleID) }
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
