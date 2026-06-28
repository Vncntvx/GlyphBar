import SwiftUI

struct MenuBarSettingsView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var settingsStore: AppSettingsStore
    @ObservedObject private var runtime: ModuleRuntime

    init(environment: AppEnvironment) {
        self.environment = environment
        self._settingsStore = ObservedObject(wrappedValue: environment.settingsStore)
        self._runtime = ObservedObject(wrappedValue: environment.runtime)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Dynamic Content Rotation", isOn: rotationEnabledBinding)
                if settingsStore.statusRotationEnabled {
                    Picker("Rotation Interval", selection: rotationIntervalBinding) {
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
                Picker("Primary Module", selection: primaryModuleBinding) {
                    ForEach(runtime.orderedModuleIDs, id: \.self) { moduleID in
                        Text(runtime.modules[moduleID]?.manifest.displayName ?? moduleID)
                            .tag(Optional(moduleID))
                    }
                }
            }
            Section {
                Toggle("Keep Panel Visible", isOn: pinPanelBinding)
            } header: {
                Text("Quick Panel")
            } footer: {
                Text("When on, the quick panel stays open when GlyphBar loses focus.")
            }
        }
        .formStyle(.grouped)
    }

    private var rotationEnabledBinding: Binding<Bool> {
        Binding(get: { settingsStore.statusRotationEnabled },
                set: { settingsStore.statusRotationEnabled = $0 })
    }

    private var rotationIntervalBinding: Binding<Int> {
        Binding(get: { settingsStore.statusRotationInterval },
                set: { settingsStore.statusRotationInterval = $0 })
    }

    private var primaryModuleBinding: Binding<ModuleID?> {
        Binding(get: { settingsStore.primaryModuleID },
                set: { settingsStore.primaryModuleID = $0 })
    }

    private var pinPanelBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.pinPanel },
            set: {
                settingsStore.pinPanel = $0
                environment.quickPanelCoordinator.applyPinPreference()
            }
        )
    }
}
