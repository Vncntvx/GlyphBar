import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var settingsStore: AppSettingsStore
    @ObservedObject private var navigation: SettingsNavigationState

    init(environment: AppEnvironment) {
        self.environment = environment
        self._settingsStore = ObservedObject(wrappedValue: environment.settingsStore)
        self._navigation = ObservedObject(wrappedValue: environment.settingsNavigation)
    }

    var body: some View {
        TabView(selection: $navigation.selectedSection) {
            Tab("General", systemImage: "gearshape", value: SettingsSection.general) {
                GeneralSettingsView(environment: environment)
            }
            Tab("Menu Bar", systemImage: "menubar.rectangle", value: SettingsSection.menuBar) {
                MenuBarSettingsView(environment: environment)
            }
            Tab("Modules", systemImage: "square.grid.2x2", value: SettingsSection.modules) {
                ModulesSettingsView(environment: environment)
            }
            Tab("Privacy", systemImage: "hand.raised", value: SettingsSection.privacy) {
                PrivacySettingsView(environment: environment)
            }
            Tab("Advanced", systemImage: "wrench.and.screwdriver", value: SettingsSection.advanced) {
                AdvancedSettingsView(environment: environment)
            }
            Tab("About", systemImage: "info.circle", value: SettingsSection.about) {
                AboutSettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .frame(width: 880, height: 580)
        .preferredColorScheme(ColorSchemeOption(rawValue: settingsStore.colorScheme)?.colorScheme)
    }
}
