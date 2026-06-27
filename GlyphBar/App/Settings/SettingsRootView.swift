import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        TabView(selection: selectedSectionBinding) {
            Form {
                Toggle("Show Dock Icon", isOn: showDockIconBinding)
                Text("Turn this off to run GlyphBar as a menu-bar-only utility. If macOS does not update the Dock immediately, relaunch GlyphBar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                Text("Launch at Login is a placeholder for the v1 shell.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(SettingsSection.general)

            Form {
                Toggle("Compact Status Title", isOn: compactStatusTitleBinding)
                Picker("Primary Module", selection: primaryModuleBinding) {
                    ForEach(environment.runtime.orderedModuleIDs, id: \.self) { moduleID in
                        Text(environment.runtime.modules[moduleID]?.manifest.displayName ?? moduleID)
                            .tag(Optional(moduleID))
                    }
                }
            }
            .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            .tag(SettingsSection.menuBar)

            ModuleManagementView(
                environment: environment,
                runtime: environment.runtime,
                settingsStore: environment.settingsStore,
                cacheStore: environment.cacheStore,
                navigation: environment.settingsNavigation
            )
            .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
            .tag(SettingsSection.modules)

            Form {
                Picker("Accent Style", selection: .constant("System")) {
                    Text("System").tag("System")
                    Text("High Contrast").tag("High Contrast")
                }
            }
            .tabItem { Label("Appearance", systemImage: "paintbrush") }
            .tag(SettingsSection.appearance)

            Form {
                Text("Clock, System Pulse, Notes Quick, Counter, and Network Mock publish lightweight cached snapshots for widgets.")
                    .foregroundStyle(.secondary)
            }
            .tabItem { Label("Widgets", systemImage: "rectangle.3.group") }
            .tag(SettingsSection.widgets)

            Form {
                ForEach(ModulePermission.allCases, id: \.self) { permission in
                    HStack {
                        Text(permission.rawValue.capitalized)
                        Spacer()
                        GlyphStatusBadge(
                            severity: environment.permissionCenter.isGranted(permission) ? .normal : .warning,
                            title: environment.permissionCenter.isGranted(permission) ? "Granted" : "Pending"
                        )
                    }
                }
            }
            .tabItem { Label("Privacy", systemImage: "hand.raised") }
            .tag(SettingsSection.privacy)

            Form {
                Button("Refresh Enabled Modules") {
                    Task {
                        await environment.runtime.refreshEnabledModules()
                    }
                }
                Button("Clear All Cached Snapshots", role: .destructive) {
                    for moduleID in environment.runtime.orderedModuleIDs {
                        environment.cacheStore.clear(moduleID: moduleID)
                    }
                }
            }
            .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
            .tag(SettingsSection.advanced)

            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                Text("GlyphBar")
                    .font(.title2.weight(.semibold))
                Text("Wenjie Xu")
                Text("wenjie.xu.cn@outlook.com")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabItem { Label("About", systemImage: "info.circle") }
            .tag(SettingsSection.about)
        }
        .frame(width: 760, height: 520)
        .scenePadding()
    }

    private var selectedSectionBinding: Binding<SettingsSection> {
        Binding(
            get: { environment.settingsNavigation.selectedSection },
            set: { environment.settingsNavigation.selectedSection = $0 }
        )
    }

    private var primaryModuleBinding: Binding<ModuleID?> {
        Binding(
            get: { environment.settingsStore.primaryModuleID },
            set: { environment.settingsStore.primaryModuleID = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { environment.settingsStore.launchAtLogin },
            set: { environment.settingsStore.launchAtLogin = $0 }
        )
    }

    private var compactStatusTitleBinding: Binding<Bool> {
        Binding(
            get: { environment.settingsStore.compactStatusTitle },
            set: { environment.settingsStore.compactStatusTitle = $0 }
        )
    }

    private var showDockIconBinding: Binding<Bool> {
        Binding(
            get: { environment.settingsStore.showDockIcon },
            set: {
                environment.settingsStore.showDockIcon = $0
                environment.applyActivationPolicy()
            }
        )
    }
}
