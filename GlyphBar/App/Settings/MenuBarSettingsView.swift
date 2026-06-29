import SwiftUI

struct MenuBarSettingsView: View {
    var environment: AppEnvironment
    @Bindable private var settingsStore: AppSettingsStore
    private var runtime: ModuleRuntime

    init(environment: AppEnvironment) {
        self.environment = environment
        self.settingsStore = environment.settingsStore
        self.runtime = environment.runtime
    }

    var body: some View {
        Form {
            Section {
                Toggle("Dynamic Content Rotation", isOn: $settingsStore.statusRotationEnabled)
                if settingsStore.statusRotationEnabled {
                    Picker("Rotation Interval", selection: $settingsStore.statusRotationInterval) {
                        Text("Every 3 seconds").tag(3)
                        Text("Every 5 seconds").tag(5)
                        Text("Every 10 seconds").tag(10)
                        Text("Every 15 seconds").tag(15)
                    }
                }
            } header: {
                Text("Status Bar Rotation")
            } footer: {
                Text("Enable per-module rotation items in Modules → select a module → Status Bar Rotation.")
            }

            Section("Primary Module") {
                Picker("Primary Module", selection: $settingsStore.primaryModuleID) {
                    ForEach(runtime.orderedModuleIDs, id: \.self) { moduleID in
                        Text(runtime.modules[moduleID]?.manifest.displayName ?? moduleID)
                            .tag(Optional(moduleID))
                    }
                }
            }
            Section {
                Toggle("Keep Panel Visible", isOn: $settingsStore.pinPanel)
                    .onChange(of: settingsStore.pinPanel) { _, _ in
                        environment.quickPanelCoordinator.applyPinPreference()
                    }
            } header: {
                Text("Quick Panel")
            } footer: {
                Text("When on, the quick panel stays open when GlyphBar loses focus.")
            }
        }
        .formStyle(.grouped)
    }
}
