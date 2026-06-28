import SwiftUI
import AppKit

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
            .shadow(color: .black.opacity(reduceTransparency ? 0.14 : 0.22), radius: 14, y: 8)
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

            // Fallback entry to the context menu. On macOS 27 Beta the status
            // item's right-click gesture may not be forwarded by the system, so
            // the menu (settings/about/quit/modules) stays reachable from here.
            GlyphToolbarButton(systemImage: "line.3.horizontal", help: "More") {
                coordinator?.showMoreMenu()
            }
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

// MARK: - Module Switcher Scroller (AppKit bridge for thin scrollbar + scroll wheel support)

private struct ModuleSwitcherScroller: NSViewRepresentable {
    struct Item {
        let id: ModuleID
        let title: String
        let systemImage: String
        let isSelected: Bool
        let severity: Severity
    }

    let items: [Item]
    let scrollToIndex: Int?
    let onSelect: (ModuleID) -> Void

    func makeNSView(context: Context) -> HScrollScrollView {
        let scrollView = HScrollScrollView()
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 12, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack
        stack.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor).isActive = true
        context.coordinator.scrollView = scrollView
        rebuild(stack, context: context)
        return scrollView
    }

    func updateNSView(_ nsView: HScrollScrollView, context: Context) {
        guard let stack = nsView.documentView as? NSStackView else { return }
        let newIDs = items.map(\.id)
        if context.coordinator.currentIDs != newIDs {
            rebuild(stack, context: context)
            context.coordinator.currentIDs = newIDs
        } else {
            for (i, item) in items.enumerated() {
                guard i < stack.arrangedSubviews.count else { break }
                if let host = stack.arrangedSubviews[i] as? NSHostingView<AnyView> {
                    host.rootView = AnyView(buttonView(for: item))
                }
            }
        }
        if let scrollToIndex, scrollToIndex != context.coordinator.lastScrollIndex {
            context.coordinator.lastScrollIndex = scrollToIndex
            DispatchQueue.main.async { nsView.scrollToIndex(scrollToIndex) }
        }
    }

    private func rebuild(_ stack: NSStackView, context: Context) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items {
            let host = NSHostingView(rootView: AnyView(buttonView(for: item)))
            host.setContentHuggingPriority(.required, for: .horizontal)
            host.setContentHuggingPriority(.required, for: .vertical)
            stack.addArrangedSubview(host)
        }
    }

    private func buttonView(for item: Item) -> some View {
        ModuleSwitchButton(
            title: item.title,
            systemImage: item.systemImage,
            isSelected: item.isSelected,
            severity: item.severity,
            action: { onSelect(item.id) }
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var scrollView: HScrollScrollView?
        var currentIDs: [ModuleID] = []
        var lastScrollIndex: Int?
    }
}

// MARK: - Thin Horizontal Scroll View

private final class HScrollScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        hasHorizontalScroller = true
        hasVerticalScroller = false
        autohidesScrollers = true
        drawsBackground = false
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let scroller = ThinScroller()
        scroller.scrollerStyle = .overlay
        horizontalScroller = scroller

        contentView.drawsBackground = false
    }

    override func scrollWheel(with event: NSEvent) {
        if event.scrollingDeltaX == 0 && event.scrollingDeltaY != 0 {
            let clip = contentView
            let newOrigin = clip.bounds.origin.x - event.scrollingDeltaY
            let maxOrigin = max(0, (documentView?.frame.width ?? 0) - clip.bounds.width)
            let clamped = max(0, min(newOrigin, maxOrigin))
            clip.scroll(to: NSPoint(x: clamped, y: 0))
            reflectScrolledClipView(clip)
        } else {
            super.scrollWheel(with: event)
        }
    }

    func scrollToIndex(_ index: Int) {
        guard let stack = documentView as? NSStackView,
              index >= 0, index < stack.arrangedSubviews.count else { return }
        let target = stack.arrangedSubviews[index]
        let frame = target.convert(target.bounds, to: contentView)
        let targetOrigin = max(0, frame.midX - contentView.bounds.width / 2)
        let maxOrigin = max(0, (documentView?.frame.width ?? 0) - contentView.bounds.width)
        let clamped = min(targetOrigin, maxOrigin)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            contentView.animator().setBoundsOrigin(NSPoint(x: clamped, y: 0))
        }
        reflectScrolledClipView(contentView)
    }
}

private final class ThinScroller: NSScroller {
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        return 6.5
    }

    override func draw(_ dirtyRect: NSRect) {
        drawKnob()
    }

    override func drawKnob() {
        let knobRect = rect(for: .knob).insetBy(dx: 0.5, dy: 1)
        let path = NSBezierPath(roundedRect: knobRect, xRadius: knobRect.height / 2, yRadius: knobRect.height / 2)
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        path.fill()
    }
}

// MARK: - Module Switcher

private struct ModuleSwitcher: View {
    @ObservedObject var runtime: ModuleRuntime

    var body: some View {
        ModuleSwitcherScroller(
            items: moduleItems,
            scrollToIndex: scrollTargetIndex,
            onSelect: { moduleID in
                runtime.setSelectedModule(moduleID)
            }
        )
        .padding(.horizontal, 8)
        .frame(height: 42)
    }

    private var moduleItems: [ModuleSwitcherScroller.Item] {
        enabledIDs.map { id in
            ModuleSwitcherScroller.Item(
                id: id,
                title: runtime.modules[id]?.manifest.displayName ?? "",
                systemImage: runtime.modules[id]?.manifest.systemImage ?? "questionmark",
                isSelected: runtime.selectedModuleID == id,
                severity: severity(for: id)
            )
        }
    }

    private var scrollTargetIndex: Int? {
        guard let selectedID = runtime.selectedModuleID,
              let index = enabledIDs.firstIndex(of: selectedID) else { return nil }
        return index
    }

    private var enabledIDs: [ModuleID] {
        runtime.enabledModuleIDs
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
                .frame(maxWidth: .infinity)
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
        module.makePanelView(context: runtime.context, snapshot: snapshot)
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
            .padding(.trailing, 4)
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

