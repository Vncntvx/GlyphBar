import SwiftUI

struct ModulesSettingsView: View {
    @ObservedObject var environment: AppEnvironment

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
