import SwiftUI

struct QuickPanelRootView: View {
    @ObservedObject var runtime: ModuleRuntime
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                PanelFooter(runtime: runtime, coordinator: coordinator)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.top, 8)
        .task {
            if runtime.selectedModuleID == nil {
                runtime.setSelectedModule(runtime.enabledModuleIDs.first)
            }
        }
    }
}

private struct PanelMaterialBackground: View {
    let reduceTransparency: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : Color.clear)
            .background {
                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
            .shadow(color: .black.opacity(reduceTransparency ? 0.14 : 0.22), radius: 18, y: 10)
            .overlay(alignment: .top) {
                Triangle()
                    .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .windowBackgroundColor).opacity(0.72))
                    .frame(width: 18, height: 9)
                    .offset(y: -7)
                    .shadow(color: .black.opacity(0.08), radius: 1, y: -1)
            }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PanelHeader: View {
    @ObservedObject var runtime: ModuleRuntime
    var coordinator: QuickPanelCoordinator?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: selectedManifest?.systemImage ?? "sparkles")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text("GlyphBar")
                    .font(.headline)
                    .lineLimit(1)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            GlyphToolbarButton(systemImage: "macwindow", help: "Open Full Window") {
                coordinator?.openFullWindow()
            }
            GlyphToolbarButton(systemImage: "gearshape", help: "Settings") {
                coordinator?.openSettings()
            }
            GlyphToolbarButton(systemImage: "xmark", help: "Close") {
                coordinator?.close()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 10)
    }

    private var selectedManifest: ModuleManifest? {
        guard let id = runtime.selectedModuleID else { return nil }
        return runtime.modules[id]?.manifest
    }

    private var statusLine: String {
        let enabledCount = runtime.enabledModuleIDs.count
        if let selectedManifest {
            return "\(selectedManifest.displayName) selected"
        }
        return enabledCount == 1 ? "1 module enabled" : "\(enabledCount) modules enabled"
    }
}

private struct ModuleSwitcher: View {
    @ObservedObject var runtime: ModuleRuntime

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(runtime.enabledModuleIDs, id: \.self) { moduleID in
                    if let module = runtime.modules[moduleID] {
                        ModuleSwitchButton(
                            title: module.manifest.displayName,
                            systemImage: module.manifest.systemImage,
                            isSelected: runtime.selectedModuleID == moduleID,
                            severity: severity(for: moduleID)
                        ) {
                            runtime.setSelectedModule(moduleID)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 34)
    }

    private func severity(for moduleID: ModuleID) -> Severity {
        runtime.snapshots[moduleID]?.signals.map(\.severity).max() ?? .normal
    }
}

private struct ModuleSwitchButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let severity: Severity
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(background, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color.accentColor.opacity(0.36) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .help(title)
    }

    private var background: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }

        switch severity {
        case .warning: return .orange.opacity(0.10)
        case .critical: return .red.opacity(0.12)
        case .info: return .blue.opacity(0.10)
        case .normal: return .clear
        }
    }
}

private struct PanelModuleContent: View {
    @ObservedObject var runtime: ModuleRuntime
    var coordinator: QuickPanelCoordinator?

    var body: some View {
        Group {
            if let moduleID = runtime.selectedModuleID,
               let module = runtime.modules[moduleID] {
                CompactModuleView(
                    runtime: runtime,
                    module: module,
                    snapshot: runtime.snapshots[moduleID]
                )
            } else {
                GlyphEmptyStateView(
                    title: "No Module Selected",
                    subtitle: "Enable a module in Settings.",
                    systemImage: "square.grid.2x2"
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
    @ObservedObject var runtime: ModuleRuntime
    let module: any StatusModule
    let snapshot: ModuleSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleSummaryBlock(module: module, snapshot: snapshot)

            CompactSnapshotDetails(snapshot: snapshot)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            ModuleActionStrip(runtime: runtime, module: module)
        }
        .padding(14)
    }
}

private struct ModuleSummaryBlock: View {
    let module: any StatusModule
    let snapshot: ModuleSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: module.manifest.systemImage)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot?.title ?? module.manifest.displayName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(snapshot?.subtitle ?? module.manifest.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)
                GlyphStatusBadge(severity: severity, title: severityTitle)
            }

            if let reason = unavailableReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var severity: Severity {
        snapshot?.signals.map(\.severity).max() ?? .normal
    }

    private var severityTitle: String {
        severity == .normal ? "Ready" : severity.rawValue.capitalized
    }

    private var color: Color {
        switch severity {
        case .normal, .info: return .accentColor
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var unavailableReason: String? {
        guard case .unavailable(let reason) = snapshot?.freshness else {
            return nil
        }
        return reason
    }
}

private struct CompactSnapshotDetails: View {
    let snapshot: ModuleSnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !metricPairs.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(metricPairs, id: \.key) { metric in
                            CompactMetricCell(title: metric.key.capitalized, value: formatted(metric.value))
                        }
                    }
                }

                if let signals = snapshot?.signals, !signals.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(signals.prefix(3)) { signal in
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(signal.title)
                                        .font(.caption.weight(.semibold))
                                    if !signal.message.isEmpty {
                                        Text(signal.message)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            } icon: {
                                Image(systemName: signal.systemImage)
                            }
                            .foregroundStyle(color(for: signal.severity))
                        }
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let notes = snapshot?.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(notes.prefix(4), id: \.self) { note in
                            Label(note, systemImage: note.hasPrefix("Pinned:") ? "pin.fill" : "text.alignleft")
                                .font(.caption)
                                .lineLimit(2)
                        }
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if metricPairs.isEmpty && snapshot?.signals.isEmpty != false && snapshot?.notes.isEmpty != false {
                    Text("No additional details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var metricPairs: [(key: String, value: Double)] {
        (snapshot?.metrics ?? [:]).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private func formatted(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private func color(for severity: Severity) -> Color {
        switch severity {
        case .normal: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

private struct CompactMetricCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ModuleActionStrip: View {
    @ObservedObject var runtime: ModuleRuntime
    let module: any StatusModule

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    Task {
                        await runtime.refresh(moduleID: module.manifest.id)
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                ForEach(module.manifest.actions) { action in
                    Button(role: action.role == .destructive ? .destructive : nil) {
                        Task {
                            await runtime.dispatch(action: action, moduleID: module.manifest.id)
                        }
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.bottom, 1)
        }
    }
}

private struct PanelFooter: View {
    @ObservedObject var runtime: ModuleRuntime
    var coordinator: QuickPanelCoordinator?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: record?.sourceKind == .thirdParty ? "shippingbox" : "checkmark.seal")
                .foregroundStyle(.secondary)
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            GlyphToolbarButton(systemImage: "pin", help: "Keep Panel Open") {
                coordinator?.pin()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var record: ModuleRecord? {
        guard let id = runtime.selectedModuleID else { return nil }
        return runtime.record(for: id)
    }

    private var footerText: String {
        guard let id = runtime.selectedModuleID,
              let module = runtime.modules[id] else {
            return "No module"
        }

        let source = record?.sourceKind.title ?? "Module"
        if let timestamp = runtime.snapshots[id]?.timestamp {
            return "\(source) · \(module.manifest.version) · \(timestamp.formatted(date: .omitted, time: .shortened))"
        }
        return "\(source) · \(module.manifest.version) · Not refreshed"
    }
}

struct ModuleDashboardWindowView: View {
    @ObservedObject var runtime: ModuleRuntime

    var body: some View {
        NavigationSplitView {
            List(selection: selectedBinding) {
                Section("Built-in") {
                    ForEach(runtime.builtInModuleIDs, id: \.self) { moduleID in
                        sidebarRow(moduleID: moduleID)
                    }
                }

                if !runtime.thirdPartyModuleIDs.isEmpty {
                    Section("Third-party") {
                        ForEach(runtime.thirdPartyModuleIDs, id: \.self) { moduleID in
                            sidebarRow(moduleID: moduleID)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 210)
        } detail: {
            DashboardModuleDetailView(runtime: runtime)
        }
        .background(GlyphGlassPanelBackground())
        .frame(minWidth: 680, minHeight: 460)
    }

    private func sidebarRow(moduleID: ModuleID) -> some View {
        Group {
            if let module = runtime.modules[moduleID] {
                let snapshot = runtime.snapshots[moduleID]
                GlyphSidebarItem(
                    title: module.manifest.displayName,
                    subtitle: snapshot?.subtitle ?? module.manifest.subtitle,
                    systemImage: module.manifest.systemImage
                )
                .tag(Optional(moduleID))
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

private struct DashboardModuleDetailView: View {
    @ObservedObject var runtime: ModuleRuntime

    var body: some View {
        Group {
            if let moduleID = runtime.selectedModuleID,
               let module = runtime.modules[moduleID] {
                DashboardModuleDetailContent(
                    runtime: runtime,
                    module: module,
                    snapshot: runtime.snapshots[moduleID]
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

private struct DashboardModuleDetailContent: View {
    @ObservedObject var runtime: ModuleRuntime
    let module: any StatusModule
    let snapshot: ModuleSnapshot?

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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial)
        }
    }
}
