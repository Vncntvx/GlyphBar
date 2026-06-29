import SwiftUI

struct AdvancedSettingsView: View {
    var environment: AppEnvironment
    private var runtime: ModuleRuntime

    init(environment: AppEnvironment) {
        self.environment = environment
        self.runtime = environment.runtime
    }

    var body: some View {
        Form {
            Section("Maintenance") {
                Button("Refresh Enabled Modules") {
                    Task { await runtime.refreshEnabledModules() }
                }
                Button("Clear All Cached Snapshots", role: .destructive) {
                    for moduleID in runtime.orderedModuleIDs {
                        environment.cacheStore.clear(moduleID: moduleID)
                    }
                }
                Button("Open Log Viewer…") {
                    environment.openLogsWindow()
                }
            }
        }
        .formStyle(.grouped)
    }
}
