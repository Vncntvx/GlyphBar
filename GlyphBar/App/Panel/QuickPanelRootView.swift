import SwiftUI

struct QuickPanelRootView: View {
    @ObservedObject var runtime: ModuleRuntime
    var coordinator: QuickPanelCoordinator?

    var body: some View {
        NavigationSplitView {
            List(selection: selectedBinding) {
                Section("Modules") {
                    ForEach(runtime.enabledModuleIDs, id: \.self) { moduleID in
                        if let module = runtime.modules[moduleID] {
                            let snapshot = runtime.snapshots[moduleID]
                            GlyphSidebarItem(
                                title: module.manifest.displayName,
                                subtitle: snapshot?.subtitle ?? module.manifest.subtitle,
                                systemImage: module.manifest.systemImage
                            )
                            .tag(moduleID)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 210)
        } detail: {
            PanelDetailView(runtime: runtime, coordinator: coordinator)
        }
        .background(GlyphGlassPanelBackground())
        .task {
            if runtime.selectedModuleID == nil {
                runtime.setSelectedModule(runtime.enabledModuleIDs.first)
            }
        }
    }

    private var selectedBinding: Binding<ModuleID?> {
        Binding(
            get: { runtime.selectedModuleID },
            set: { runtime.setSelectedModule($0) }
        )
    }
}

private struct PanelDetailView: View {
    @ObservedObject var runtime: ModuleRuntime
    var coordinator: QuickPanelCoordinator?

    var body: some View {
        Group {
            if let moduleID = runtime.selectedModuleID,
               let module = runtime.modules[moduleID] {
                ModuleDetailView(
                    runtime: runtime,
                    module: module,
                    snapshot: runtime.snapshots[moduleID],
                    coordinator: coordinator
                )
            } else {
                GlyphEmptyStateView(
                    title: "No Module Selected",
                    subtitle: "Enable a module in Settings or choose one from the sidebar.",
                    systemImage: "square.grid.2x2"
                )
            }
        }
        .frame(minWidth: 460, minHeight: 420)
    }
}

private struct ModuleDetailView: View {
    @ObservedObject var runtime: ModuleRuntime
    let module: any StatusModule
    let snapshot: ModuleSnapshot?
    var coordinator: QuickPanelCoordinator?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GlyphModuleHeader(
                    title: module.manifest.displayName,
                    subtitle: snapshot?.subtitle ?? module.manifest.subtitle,
                    systemImage: module.manifest.systemImage,
                    severity: snapshot?.signals.map(\.severity).max() ?? .normal
                )

                module.makePanelView(context: runtime.context, snapshot: snapshot)

                if !module.manifest.actions.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(module.manifest.actions) { action in
                            GlyphActionButton(
                                title: action.title,
                                systemImage: action.systemImage,
                                role: action.role
                            ) {
                                Task {
                                    await runtime.dispatch(action: action, moduleID: module.manifest.id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                GlyphToolbarButton(systemImage: "arrow.clockwise", help: "Refresh") {
                    Task {
                        await runtime.refresh(moduleID: module.manifest.id)
                    }
                }
                GlyphToolbarButton(systemImage: "pin", help: "Keep panel open") {
                    coordinator?.pin()
                }
                GlyphToolbarButton(systemImage: "xmark", help: "Close") {
                    coordinator?.close()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial)
        }
    }
}
