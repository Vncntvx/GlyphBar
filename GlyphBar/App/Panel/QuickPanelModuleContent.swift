import SwiftUI

struct PanelModuleContent: View {
    var runtime: ModuleRuntime
    var coordinator: QuickPanelCoordinator?

    var body: some View {
        Group {
            if let moduleID = runtime.selectedModuleID,
               let module = runtime.modules[moduleID],
               runtime.enabledModuleIDs.contains(moduleID) {
                CompactModuleView(runtime: runtime, module: module)
                    .frame(maxWidth: .infinity)
            } else {
                GlyphEmptyStateView(
                    title: runtime.enabledModuleIDs.isEmpty
                        ? "No Modules Enabled" : "No Module Selected",
                    subtitle: runtime.enabledModuleIDs.isEmpty
                        ? "Enable a module in Settings to get started."
                        : "Choose a module from the tab bar or enable one in Settings.",
                    systemImage: runtime.enabledModuleIDs.isEmpty
                        ? "square.dashed" : "square.grid.2x2"
                )
                .overlay(alignment: .bottom) {
                    Button("Open Settings") {
                        coordinator?.openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.bottom, 16)
                }
            }
        }
    }
}

private struct CompactModuleView: View {
    var runtime: ModuleRuntime
    let module: any ModuleContract

    var body: some View {
        if let contribution = module as? any TypedModuleContribution {
            ModulePanelHost(contribution: contribution, runtime: runtime)
        } else {
            Text("No panel available")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ModulePanelHost: View {
    let contribution: any TypedModuleContribution
    let runtime: ModuleRuntime

    var body: some View {
        let context = PanelHostContext(moduleID: contribution.manifest.id) { command in
            runtime.dispatch(command: command, moduleID: contribution.manifest.id)
        }
        return contribution.panelContribution(context: context)
    }
}
