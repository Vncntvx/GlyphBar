import Foundation

/// The final decision the arbiter hands to `StatusItemRenderer` (P1.14).
/// `Equatable` so the renderer can skip no-op re-renders.
struct PresentationDecision: Equatable {
    var title: String
    var systemImage: String
    var severity: Severity
    var tooltip: String
    var accessibilityLabel: String
    var accessibilityHint: String
    var sourceModule: String?
    var isCritical: Bool

    init(
        title: String = "",
        systemImage: String = "circle",
        severity: Severity = .normal,
        tooltip: String = "",
        accessibilityLabel: String = "",
        accessibilityHint: String = "",
        sourceModule: String? = nil,
        isCritical: Bool = false
    ) {
        self.title = title
        self.systemImage = systemImage
        self.severity = severity
        self.tooltip = tooltip
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.sourceModule = sourceModule
        self.isCritical = isCritical
    }
}
