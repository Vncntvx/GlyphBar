import AppKit
import SwiftUI

struct ModuleSwitcher: View {
    var runtime: ModuleRuntime

    var body: some View {
        ModuleSwitcherScroller(
            moduleIDs: runtime.enabledModuleIDs,
            runtime: runtime,
            scrollToIndex: runtime.enabledModuleIDs.firstIndex(of: runtime.selectedModuleID ?? "")
        )
        .padding(.horizontal, 8)
        .frame(height: 42)
    }
}

private struct ModuleSwitcherScroller: NSViewRepresentable {
    let moduleIDs: [ModuleID]
    let runtime: ModuleRuntime
    let scrollToIndex: Int?

    func makeNSView(context: Context) -> HScrollScrollView {
        let scrollView = HScrollScrollView()
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 4, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack
        stack.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor).isActive = true
        context.coordinator.scrollView = scrollView
        rebuild(stack, context: context)
        return scrollView
    }

    func updateNSView(_ nsView: HScrollScrollView, context: Context) {
        guard let stack = nsView.documentView as? NSStackView else { return }
        if context.coordinator.currentIDs != moduleIDs {
            rebuild(stack, context: context)
            context.coordinator.currentIDs = moduleIDs
        }
        if let index = scrollToIndex, index != context.coordinator.lastScrollIndex {
            context.coordinator.lastScrollIndex = index
            nsView.scrollToIndex(index)
        }
    }

    private func rebuild(_ stack: NSStackView, context: Context) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for moduleID in moduleIDs {
            let host = NSHostingView(rootView: ModuleTabButtonHost(moduleID: moduleID, runtime: runtime))
            host.setContentHuggingPriority(.required, for: .horizontal)
            host.setContentHuggingPriority(.required, for: .vertical)
            stack.addArrangedSubview(host)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var scrollView: HScrollScrollView?
        var currentIDs: [ModuleID] = []
        var lastScrollIndex: Int?
    }
}

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

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let scrollerHit = horizontalScroller?.hitTest(point) {
            return scrollerHit
        }
        if let docView = documentView {
            let docPoint = convert(point, to: docView)
            return docView.hitTest(docPoint) ?? super.hitTest(point)
        }
        return super.hitTest(point)
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
        contentView.setBoundsOrigin(NSPoint(x: clamped, y: 0))
        reflectScrolledClipView(contentView)
    }
}

private final class ThinScroller: NSScroller {
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        6.5
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

private struct ModuleTabButtonHost: View {
    let moduleID: ModuleID
    var runtime: ModuleRuntime

    var body: some View {
        let manifest = runtime.modules[moduleID]?.manifest
        let isSelected = runtime.selectedModuleID == moduleID
        let severity = runtime.snapshots[moduleID]?.signals.map(\.severity).max() ?? .normal

        ModuleSwitchButton(
            title: manifest?.displayName ?? "",
            systemImage: manifest?.systemImage ?? "questionmark",
            isSelected: isSelected,
            severity: severity,
            action: { runtime.setSelectedModule(moduleID) }
        )
    }
}

private struct ModuleSwitchButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let severity: Severity
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .lineLimit(1)
            if !isSelected, severity >= .warning {
                Circle()
                    .fill(severity == .critical ? Color.red : Color.orange)
                    .frame(width: 5, height: 5)
            }
        }
        .font(.caption.weight(isSelected ? .semibold : .regular))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background(background, in: Capsule())
        .overlay {
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        }
        .contentShape(.interaction, Capsule())
        .onTapGesture { action() }
        .help(title)
    }

    private var background: Color {
        isSelected ? Color.accentColor.opacity(0.16) : .clear
    }

    private var borderColor: Color {
        isSelected ? Color.accentColor.opacity(0.36) : Color.primary.opacity(0.08)
    }
}
