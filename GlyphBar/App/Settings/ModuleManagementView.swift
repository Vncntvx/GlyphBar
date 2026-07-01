import SwiftUI

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
