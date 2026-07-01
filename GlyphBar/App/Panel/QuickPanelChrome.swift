import SwiftUI

struct PanelMaterialBackground: View {
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
            .shadow(color: .black.opacity(reduceTransparency ? 0.14 : 0.22), radius: 14, y: 8)
    }
}

struct PanelHeader: View {
    var runtime: ModuleRuntime
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

            GlyphToolbarButton(systemImage: "gearshape", help: "Settings") {
                coordinator?.openSettings()
            }
            GlyphToolbarButton(systemImage: "xmark", help: "Close") {
                coordinator?.close()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
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

struct PanelFooter: View {
    var runtime: ModuleRuntime
    var coordinator: QuickPanelCoordinator?
    @State private var isPinned = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: record?.sourceKind == .thirdParty ? "shippingbox" : "checkmark.seal")
                .font(.caption)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            GlyphToolbarButton(
                systemImage: isPinned ? "pin.fill" : "pin",
                help: isPinned ? "Unpin Panel" : "Keep Panel Open"
            ) {
                coordinator?.pin()
                isPinned.toggle()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onAppear {
            isPinned = coordinator?.isPinned ?? false
        }
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
