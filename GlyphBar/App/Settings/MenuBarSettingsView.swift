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
            Section("Status") {
                Toggle("Compact Status Title", isOn: compactBinding)
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

    private var compactBinding: Binding<Bool> {
        Binding(get: { settingsStore.compactStatusTitle },
                set: { settingsStore.compactStatusTitle = $0 })
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
