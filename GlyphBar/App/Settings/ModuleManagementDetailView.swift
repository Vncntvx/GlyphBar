import SwiftUI

struct ModuleManagementDetailView: View {
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
                    refreshSection(module: module)
                    if selectedModuleID == "deepseek" {
                        deepSeekSection
                    }
                    rotationSection(module: module)
                    controlsSection(module: module, record: record)
                    metadataSection(module: module, record: record)
                    capabilitiesSection(module: module)
                    permissionsSection(module: module)
                    widgetsSection(module: module)
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

    private func refreshSection(module: any ModuleContract) -> some View {
        Section {
            Picker(
                "Schedule",
                selection: refreshPolicyBinding(
                    moduleID: module.manifest.id,
                    defaultPolicy: module.manifest.defaultRefreshPolicy
                )
            ) {
                Text("Manual").tag(RefreshPolicy.manual)
                Text("On Launch").tag(RefreshPolicy.onLaunch)
                Text("Every 5s").tag(RefreshPolicy.interval(seconds: 5))
                Text("Every 30s").tag(RefreshPolicy.interval(seconds: 30))
                Text("Every 60s").tag(RefreshPolicy.interval(seconds: 60))
                Text("Every 30m").tag(RefreshPolicy.interval(seconds: 1800))
                Text("Every 60m").tag(RefreshPolicy.interval(seconds: 3600))
                if let custom = customIntervalTag(
                    for: module.manifest.id,
                    defaultPolicy: module.manifest.defaultRefreshPolicy
                ) {
                    Text("Custom (\(Int(custom.minimumInterval ?? 0))s)").tag(custom)
                }
            }
        } header: {
            Text("Refresh")
        } footer: {
            Text("Controls how often this module publishes a fresh snapshot.")
        }
    }

    private var deepSeekSection: some View {
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

    private func rotationSection(module: any ModuleContract) -> some View {
        Section {
            Toggle("Include in Status Bar Rotation", isOn: rotationModuleBinding(module.manifest.id))
            let candidates = module.statusCandidates()
            if !candidates.isEmpty && settingsStore.rotationModuleIDs.contains(module.manifest.id) {
                ForEach(candidates) { candidate in
                    Toggle(candidate.text, isOn: rotationItemBinding(moduleID: module.manifest.id, itemID: candidate.id))
                }
            }
        } header: {
            Text("Status Bar Rotation")
        } footer: {
            Text("Choose which information to show when cycling through modules in the status bar.")
        }
    }

    private func controlsSection(module: any ModuleContract, record: ModuleRecord) -> some View {
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
                    Button("Remove Module...", role: .destructive) { remove(moduleID: module.manifest.id) }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func metadataSection(module: any ModuleContract, record: ModuleRecord) -> some View {
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
    }

    private func capabilitiesSection(module: any ModuleContract) -> some View {
        Section("Capabilities") {
            if module.manifest.capabilities.isEmpty {
                Text("None").font(.caption).foregroundStyle(.secondary)
            } else {
                FlowLayout(items: module.manifest.capabilities.map(\.rawValue)) { title in
                    GlyphStatusBadge(severity: .normal, title: title)
                }
            }
        }
    }

    private func permissionsSection(module: any ModuleContract) -> some View {
        Section("Permissions") {
            if module.manifest.permissions.isEmpty {
                Text("No extra permissions requested.").font(.caption).foregroundStyle(.secondary)
            } else {
                FlowLayout(items: module.manifest.permissions.map(\.rawValue)) { title in
                    GlyphStatusBadge(severity: .warning, title: title)
                }
            }
        }
    }

    private func widgetsSection(module: any ModuleContract) -> some View {
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

    private func refreshPolicyBinding(moduleID: ModuleID, defaultPolicy: RefreshPolicy) -> Binding<RefreshPolicy> {
        Binding(
            get: { settingsStore.refreshPolicies[moduleID] ?? defaultPolicy },
            set: { settingsStore.setRefreshPolicy($0, for: moduleID) }
        )
    }

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
