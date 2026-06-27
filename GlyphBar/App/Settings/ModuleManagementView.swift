import SwiftUI

struct ModuleManagementView: View {
    @ObservedObject var runtime: ModuleRuntime
    @ObservedObject var settingsStore: AppSettingsStore
    let cacheStore: CacheStore

    var body: some View {
        List {
            ForEach(runtime.orderedModuleIDs, id: \.self) { moduleID in
                if let module = runtime.modules[moduleID] {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: module.manifest.systemImage)
                                .font(.title3)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(module.manifest.displayName)
                                    .font(.headline)
                                Text(module.manifest.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                            Toggle("Enabled", isOn: enabledBinding(moduleID))
                                .labelsHidden()
                        }

                        HStack {
                            Button {
                                settingsStore.move(moduleID: moduleID, direction: -1)
                            } label: {
                                Image(systemName: "arrow.up")
                            }
                            .help("Move up")

                            Button {
                                settingsStore.move(moduleID: moduleID, direction: 1)
                            } label: {
                                Image(systemName: "arrow.down")
                            }
                            .help("Move down")

                            Button("Set Primary") {
                                settingsStore.primaryModuleID = moduleID
                            }

                            Button("Reset Cache", role: .destructive) {
                                settingsStore.resetModuleState(moduleID: moduleID, cacheStore: cacheStore)
                            }

                            Spacer()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func enabledBinding(_ moduleID: ModuleID) -> Binding<Bool> {
        Binding(
            get: { settingsStore.isEnabled(moduleID) },
            set: { settingsStore.setEnabled($0, moduleID: moduleID) }
        )
    }
}
