import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var settingsStore: AppSettingsStore

    init(environment: AppEnvironment) {
        self.environment = environment
        self._settingsStore = ObservedObject(wrappedValue: environment.settingsStore)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show Dock Icon", isOn: dockIconBinding)
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
            } header: {
                Text("Startup")
            } footer: {
                Text("Turn off \"Show Dock Icon\" to run as a menu-bar-only utility. \"Launch at Login\" starts GlyphBar when you log in.")
            }
            Section("Appearance") {
                Picker("Color Scheme", selection: colorSchemeBinding) {
                    ForEach(ColorSchemeOption.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var dockIconBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.showDockIcon },
            set: {
                settingsStore.showDockIcon = $0
                environment.applyActivationPolicy()
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.launchAtLogin },
            set: {
                settingsStore.launchAtLogin = $0
                environment.applyLaunchAtLogin()
            }
        )
    }

    private var colorSchemeBinding: Binding<String> {
        Binding(
            get: { settingsStore.colorScheme },
            set: { settingsStore.colorScheme = $0 }
        )
    }
}
