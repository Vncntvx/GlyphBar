import SwiftUI

struct QuickPanelRootView: View {
    var runtime: ModuleRuntime
    var coordinator: QuickPanelCoordinator?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .top) {
            PanelMaterialBackground(reduceTransparency: reduceTransparency)

            VStack(spacing: 0) {
                PanelHeader(runtime: runtime, coordinator: coordinator)

                Divider()

                ModuleSwitcher(runtime: runtime)
                    .padding(.vertical, 8)

                Divider()

                PanelModuleContent(runtime: runtime, coordinator: coordinator)

                Divider()

                PanelFooter(runtime: runtime, coordinator: coordinator)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onResize { coordinator?.resizePanel(to: $0) }
        }
        .task {
            if runtime.selectedModuleID == nil {
                runtime.setSelectedModule(runtime.enabledModuleIDs.first)
            }
        }
    }
}
