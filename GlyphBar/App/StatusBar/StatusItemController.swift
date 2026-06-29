import AppKit
import Combine

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
    private let runtime: ModuleRuntime
    private let settingsStore: AppSettingsStore
    private let panelCoordinator: QuickPanelCoordinator
    private let menuCoordinator: AppMenuCoordinator
    private let logger: GlyphLogger
    // P1.14: arbiter + renderer replace composer + rotationEngine.
    private let arbiter = PresentationArbiter(fallback: PresentationDecision(
        title: "GlyphBar",
        systemImage: "sparkles",
        severity: .normal,
        tooltip: "GlyphBar"
    ))
    private let renderer: StatusItemRenderer
    private let presentationTicker = PresentationTicker()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables: Set<AnyCancellable> = []
    private var pendingRender: DispatchWorkItem?
    private var isPresentingContextMenu = false
    private var isEndingExpandedSession = false
    private var secondaryClickRecognizer: NSClickGestureRecognizer?

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

    // MARK: - Appearance (every OS)

    private func configureAppearance() {
        guard let button = statusItem.button else {
            return
        }
        button.imagePosition = .imageLeft
        button.toolTip = "GlyphBar"
        // No static menu: a bound menu would make the system manage the item as
        // a menu and suppress macOS 27 expanded-interface callbacks. The
        // context menu is popped manually from the right-click gesture.
        statusItem.menu = nil
        button.menu = nil
    }

    // MARK: - Interaction (OS-dependent)

    private func configureInteraction() {
        attachSecondaryClickGestureRecognizer()

        if #available(macOS 27.0, *) {
            // Left-click is owned by the expanded interface session. Do not set
            // button.target/action on this path.
            statusItem.expandedInterfaceDelegate = self
            // Close the panel when it loses focus (user clicked elsewhere):
            // resignKey → close() → cancel the active expanded session.
            panelCoordinator.dismissOnResignKey = true
            // Do not let AppKit auto-hide the panel on deactivation: on macOS 27
            // that hides the panel while the expanded session stays "active",
            // leaving the menu bar unclickable. Losing focus closes it instead.
            panelCoordinator.panelHidesOnDeactivate = false
            panelCoordinator.onPanelHidden = { [weak self] in
                self?.handlePanelHiddenByUserAction()
            }
            logger.statusItem("primary activation: expanded interface delegate (macOS 27+)")
        } else {
            // macOS 26 and earlier: target/action on left mouse-up only.
            // Right-click is consumed by the gesture recognizer above, so the
            // button action never needs to distinguish button type — no
            // currentEvent inspection, no shared left/right action.
            guard let button = statusItem.button else {
                return
            }
            button.target = self
            button.action = #selector(handlePrimaryClickLegacy(_:))
            button.sendAction(on: [.leftMouseUp])
            logger.statusItem("primary activation: target/action (macOS 26 and earlier)")
        }
    }

    private func attachSecondaryClickGestureRecognizer() {
        guard let button = statusItem.button else {
            return
        }
        let recognizer = NSClickGestureRecognizer()
        recognizer.target = self
        recognizer.action = #selector(handleSecondaryClick(_:))
        // 1 << 1 selects the secondary (right) button only. Primary clicks are
        // left to the expanded interface (macOS 27) or the button action (<=26).
        recognizer.buttonMask = 1 << 1
        // NOTE: Apple has acknowledged a macOS 27 Beta regression where status
        // item secondary-click events may not be forwarded at all. If this
        // recognizer fails to fire on macOS 27 Beta, do NOT work around it with
        // global event monitors, CGEventTap, or Input Monitoring — none of those
        // are acceptable here. The context menu remains reachable via the
        // "More" button inside the quick panel (see QuickPanelCoordinator.showMoreMenu).
        button.addGestureRecognizer(recognizer)
        secondaryClickRecognizer = recognizer
    }

    // MARK: - Legacy left-click (macOS 26 and earlier)

    @objc private func handlePrimaryClickLegacy(_ sender: NSStatusBarButton) {
        logger.statusItem("primary activation (target-action)")
        panelCoordinator.toggle(relativeTo: statusItem)
    }

    // MARK: - Right-click (every OS, fully separated from left-click)

    @objc private func handleSecondaryClick(_ recognizer: NSClickGestureRecognizer) {
        logger.statusItem("secondary gesture recognized")
        // Mutual exclusion: end any active expanded session and hide the panel
        // before showing the context menu.
        if #available(macOS 27.0, *), let session = statusItem.expandedInterfaceSession {
            session.cancel()
        }
        panelCoordinator.close()
        // Defer the modal popUp to the next runloop turn so any synchronous
        // didEnd callback from cancel() has fully unwound first. Weak-captured
        // to avoid a retain cycle through the async closure.
        DispatchQueue.main.async { [weak self] in
            self?.presentContextMenu()
        }
    }

    private func presentContextMenu() {
        guard !isPresentingContextMenu else {
            return
        }
        isPresentingContextMenu = true
        defer { isPresentingContextMenu = false }

        let menu = menuCoordinator.makeMenu()
        let point = contextMenuAnchorPoint()
        logger.statusItem("menu popup")
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    private func contextMenuAnchorPoint() -> NSPoint {
        guard let button = statusItem.button,
              let window = button.window else {
            return .zero
        }
        let frameInWindow = button.convert(button.bounds, to: nil)
        let screenFrame = window.convertToScreen(frameInWindow)
        return NSPoint(x: screenFrame.minX, y: screenFrame.minY - 2)
    }

    // MARK: - Expanded session sync (macOS 27+)

    /// Called whenever the panel is hidden by something other than the system
    /// ending the expanded session (close button, settings, full window, or —
    /// the main path — losing focus / resignKey). Cancels the still-active
    /// session so the status item does not stay stuck in the expanded state.
    private func handlePanelHiddenByUserAction() {
        guard !isEndingExpandedSession else {
            return
        }
        if #available(macOS 27.0, *), let session = statusItem.expandedInterfaceSession {
            logger.statusItem("panel hidden while session active; cancelling expanded session")
            session.cancel()
        }
    }

    // MARK: - Rendering (P1.14: arbiter + renderer)

    private func observeRuntime() {
        runtime.$snapshots
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.submitCandidatesToArbiter()
                self?.scheduleRender()
            }
            .store(in: &cancellables)

        settingsStore.$primaryModuleID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.submitCandidatesToArbiter()
                self?.scheduleRender()
            }
            .store(in: &cancellables)

        settingsStore.$enabledModuleIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.submitCandidatesToArbiter()
                self?.updateRotationTimer()
                self?.scheduleRender()
            }
            .store(in: &cancellables)

        settingsStore.$statusRotationEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateRotationTimer()
                self?.scheduleRender()
            }
            .store(in: &cancellables)

        settingsStore.$statusRotationInterval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateRotationTimer()
            }
            .store(in: &cancellables)

        settingsStore.$rotationModuleIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.submitCandidatesToArbiter()
                self?.updateRotationTimer()
                self?.scheduleRender()
            }
            .store(in: &cancellables)

        settingsStore.$rotationItemIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.submitCandidatesToArbiter()
                self?.scheduleRender()
            }
            .store(in: &cancellables)
    }

    /// Collects `StatusCandidate`s from all enabled modules and submits them
    /// to the arbiter. All modules now implement `ModuleContract` and
    /// `statusCandidates()` directly.
    private func submitCandidatesToArbiter() {
        var candidates: [StatusCandidate] = []
        let enabledSnapshots = runtime.snapshots.filter { settingsStore.isEnabled($0.key) }

        for (id, snapshot) in enabledSnapshots {
            if let module = runtime.modules[id] as? any ModuleContract {
                candidates.append(contentsOf: module.statusCandidates())
            } else {
                // Fallback: derive candidates from snapshot signals.
                let projection = ProjectionBuilder.build(from: snapshot)
                candidates.append(contentsOf: projection.statusCandidates)
            }
        }

        // P1.14: respect rotationModuleIDs filter — only those modules
        // contribute rotation candidates. Critical/primary candidates are
        // always included.
        if !settingsStore.rotationModuleIDs.isEmpty {
            candidates = candidates.filter { candidate in
                if candidate.semanticRole == .rotation {
                    return settingsStore.rotationModuleIDs.contains(candidate.sourceModule)
                }
                return true
            }
        }

        arbiter.submit(candidates, now: Date())
    }

    private func updateRotationTimer() {
        presentationTicker.stop()
        guard settingsStore.statusRotationEnabled else { return }
        let interval = TimeInterval(settingsStore.statusRotationInterval)
        presentationTicker.start(interval: interval) { [weak self] in
            guard let self else { return }
            // P2: presentation ticker drives the arbiter tick, which
            // cycles through rotation candidates and applies TTL/hysteresis.
            // Also run presentationTick on PresentationTickable modules.
            self.runPresentationTicks()
            _ = self.arbiter.tick(now: Date())
            self.renderer.render(self.arbiter.currentDecision)
        }
    }

    /// Run presentationTick on all PresentationTickable modules.
    /// This updates their display projections without triggering data refresh.
    private func runPresentationTicks() {
        for (id, module) in runtime.modules {
            if let tickable = module as? any PresentationTickable {
                let projection = tickable.buildProjection()
                let _ = tickable.presentationTick(trigger: .timerTick, projection: projection)
                // Re-submit candidates after tick to update arbiter
                let candidates = tickable.statusCandidates()
                if !candidates.isEmpty {
                    // Merge with existing arbiter candidates
                    var allCandidates = self.collectAllCandidates()
                    // Replace this module's candidates
                    allCandidates.removeAll { $0.sourceModule == id }
                    allCandidates.append(contentsOf: candidates)
                    arbiter.submit(allCandidates, now: Date())
                }
            }
        }
    }

    /// Collect candidates from all enabled modules (used by runPresentationTicks).
    private func collectAllCandidates() -> [StatusCandidate] {
        var candidates: [StatusCandidate] = []
        let enabledSnapshots = runtime.snapshots.filter { settingsStore.isEnabled($0.key) }

        for (id, snapshot) in enabledSnapshots {
            if let module = runtime.modules[id] as? any ModuleContract {
                candidates.append(contentsOf: module.statusCandidates())
            } else {
                let projection = ProjectionBuilder.build(from: snapshot)
                candidates.append(contentsOf: projection.statusCandidates)
            }
        }

        if !settingsStore.rotationModuleIDs.isEmpty {
            candidates = candidates.filter { candidate in
                if candidate.semanticRole == .rotation {
                    return settingsStore.rotationModuleIDs.contains(candidate.sourceModule)
                }
                return true
            }
        }

        return candidates
    }

    private func scheduleRender() {
        pendingRender?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.render()
            }
        }
        pendingRender = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func render() {
        // P1.14: single path — renderer writes the arbiter's current decision.
        renderer.render(arbiter.currentDecision)
    }
}

// MARK: - NSStatusItemExpandedInterfaceDelegate (macOS 27+)
//
// AppKit invokes these on the main thread. They are `nonisolated` to satisfy
// the non-isolated @objc protocol requirement, then re-enter the main actor
// synchronously via `MainActor.assumeIsolated` (guaranteed safe because AppKit
// dispatches status item delegate callbacks on the main thread).

@available(macOS 27.0, *)
extension StatusItemController: NSStatusItemExpandedInterfaceDelegate {
    nonisolated func statusItem(
        _ statusItem: NSStatusItem,
        didBegin session: NSStatusItemExpandedInterfaceSession
    ) {
        MainActor.assumeIsolated {
            logger.statusItem("expanded session begin")
            panelCoordinator.show(relativeTo: statusItem)
        }
    }

    nonisolated func statusItemDidEndExpandedInterfaceSession(
        _ statusItem: NSStatusItem,
        animated: Bool
    ) {
        MainActor.assumeIsolated {
            logger.statusItem("expanded session end (animated: \(animated))")
            isEndingExpandedSession = true
            defer { isEndingExpandedSession = false }
            guard !settingsStore.pinPanel else {
                logger.statusItem("panel pinned — keeping open")
                return
            }
            panelCoordinator.close()
        }
    }
}
