import AppKit
import Foundation

/// The single owner of the menu bar status item and its interaction model.
///
/// Left-click and right-click are fully separated and never share an action:
///
/// - **Right-click** (every OS) is handled by a dedicated
///   `NSClickGestureRecognizer` with `buttonMask = 1 << 1` (secondary button
///   only) that manually pops the context menu via
///   `NSMenu.popUp(positioning:at:in:)`. It never inspects `currentEvent`.
///
/// - **Left-click** uses one of two runtime-selected paths:
///   - macOS 27+: `statusItem.expandedInterfaceDelegate`. The system calls
///     `statusItem(_:didBegin:)` to show the quick panel and
///     `statusItemDidEndExpandedInterfaceSession(_:animated:)` to hide it.
///     Clicking the item again collapses the expanded interface (closing the
///     panel); dismissing the panel by other user action calls
///     `expandedInterfaceSession?.cancel()`.
///   - macOS 26 and earlier: `button.sendAction(on: [.leftMouseUp])` with a
///     target/action that toggles the panel. Right-click is consumed by the
///     gesture recognizer, so this action never has to distinguish button type.
///
/// On macOS 27 the panel closes simply by losing focus: when the user clicks
/// elsewhere the panel resigns key → `close()` → the active expanded session is
/// cancelled (→ `didEnd`). `hidesOnDeactivate` is false on macOS 27 because
/// AppKit auto-hiding the panel leaves the expanded session "active" and the
/// menu bar unclickable. `statusItem.menu` / `button.menu` are intentionally
/// `nil` on every OS: a statically bound menu suppresses the macOS 27 expanded
/// interface callbacks.
@MainActor
final class StatusItemController: NSObject {
    let runtime: ModuleRuntime
    let settingsStore: AppSettingsStore
    let panelCoordinator: QuickPanelCoordinator
    let menuCoordinator: AppMenuCoordinator
    let logger: GlyphLogger
    // P1.14: arbiter + renderer replace composer + rotationEngine.
    let arbiter = PresentationArbiter(fallback: PresentationDecision(
        title: "GlyphBar",
        systemImage: "sparkles",
        severity: .normal,
        tooltip: "GlyphBar"
    ))
    let renderer: StatusItemRenderer
    let presentationTicker = PresentationTicker()
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var renderTask: Task<Void, Never>?
    var isPresentingContextMenu = false
    var isEndingExpandedSession = false
    var secondaryClickRecognizer: NSClickGestureRecognizer?

    init(
        runtime: ModuleRuntime,
        settingsStore: AppSettingsStore,
        panelCoordinator: QuickPanelCoordinator,
        menuCoordinator: AppMenuCoordinator,
        logger: GlyphLogger
    ) {
        self.runtime = runtime
        self.settingsStore = settingsStore
        self.panelCoordinator = panelCoordinator
        self.menuCoordinator = menuCoordinator
        self.logger = logger
        self.renderer = StatusItemRenderer(statusItem: statusItem)
        super.init()
    }

    func start() {
        logger.statusItem(
            "status item controller started on \(ProcessInfo.processInfo.operatingSystemVersionString)"
        )
        configureAppearance()
        configureInteraction()
        observeRuntime()
        submitCandidatesToArbiter()
        updateRotationTimer()
        render()
    }
}
