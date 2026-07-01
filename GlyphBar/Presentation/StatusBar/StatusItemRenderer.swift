import AppKit

/// Renders a `PresentationDecision` to the menu bar status item.
///
/// The controller now owns a `PresentationArbiter` (decides what to show) and a
/// `StatusItemRenderer` (writes the decision to the NSStatusItem button).
@MainActor
final class StatusItemRenderer {
    private let statusItem: NSStatusItem

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
    }

    /// Writes `decision` to the status item button. No-op if the button is
    /// unavailable (e.g. during teardown). Skips work when the decision is
    /// unchanged from the previous render (callers can compare via
    /// `PresentationDecision ==` before calling if they prefer).
    func render(_ decision: PresentationDecision) {
        guard let button = statusItem.button else { return }

        button.title = decision.title.isEmpty ? "" : " \(decision.title)"
        button.image = NSImage(
            systemSymbolName: decision.systemImage,
            accessibilityDescription: decision.accessibilityLabel.isEmpty ? decision.title : decision.accessibilityLabel
        )
        button.imagePosition = .imageLeft
        button.toolTip = decision.tooltip.isEmpty ? decision.title : decision.tooltip

        // Accessibility: expose the decision as the button's accessibility label
        // so VoiceOver users get the same information as visual users.
        button.setAccessibilityLabel(decision.accessibilityLabel.isEmpty ? decision.title : decision.accessibilityLabel)
        if !decision.accessibilityHint.isEmpty {
            button.setAccessibilityHelp(decision.accessibilityHint)
        }
    }
}
