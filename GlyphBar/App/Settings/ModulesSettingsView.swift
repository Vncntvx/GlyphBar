import SwiftUI

struct ModulesSettingsView: View {
    var environment: AppEnvironment

    var body: some View {
        ModuleManagementView(
            environment: environment,
            runtime: environment.runtime,
            settingsStore: environment.settingsStore,
            cacheStore: environment.cacheStore,
            navigation: environment.settingsNavigation
        )
    }
}
