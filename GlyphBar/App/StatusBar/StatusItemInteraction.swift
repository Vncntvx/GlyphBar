import AppKit

extension StatusItemController {
    // MARK: - Appearance (every OS)

    func configureAppearance() {
        guard let button = statusItem.button else {
            return
        }
        button.imagePosition = .imageLeft
        button.toolTip = "GlyphBar"
        statusItem.menu = nil
        button.menu = nil
    }

    // MARK: - Interaction (OS-dependent)

    func configureInteraction() {
        attachSecondaryClickGestureRecognizer()

        if #available(macOS 27.0, *) {
            statusItem.expandedInterfaceDelegate = self
            panelCoordinator.dismissOnResignKey = true
            panelCoordinator.panelHidesOnDeactivate = false
            panelCoordinator.onPanelHidden = { [weak self] in
                self?.handlePanelHiddenByUserAction()
            }
            logger.statusItem("primary activation: expanded interface delegate (macOS 27+)")
        } else {
            guard let button = statusItem.button else {
                return
            }
            button.target = self
            button.action = #selector(handlePrimaryClickLegacy(_:))
            button.sendAction(on: [.leftMouseUp])
            logger.statusItem("primary activation: target/action (macOS 26 and earlier)")
        }
    }

    func attachSecondaryClickGestureRecognizer() {
        guard let button = statusItem.button else {
            return
        }
        let recognizer = NSClickGestureRecognizer()
        recognizer.target = self
        recognizer.action = #selector(handleSecondaryClick(_:))
        recognizer.buttonMask = 1 << 1
        button.addGestureRecognizer(recognizer)
        secondaryClickRecognizer = recognizer
    }

    // MARK: - Legacy left-click (macOS 26 and earlier)

    @objc func handlePrimaryClickLegacy(_ sender: NSStatusBarButton) {
        logger.statusItem("primary activation (target-action)")
        panelCoordinator.toggle(relativeTo: statusItem)
    }

    // MARK: - Right-click (every OS)

    @objc func handleSecondaryClick(_ recognizer: NSClickGestureRecognizer) {
        logger.statusItem("secondary gesture recognized")
        if #available(macOS 27.0, *), let session = statusItem.expandedInterfaceSession {
            session.cancel()
        }
        panelCoordinator.close()
        Task { @MainActor [weak self] in
            self?.presentContextMenu()
        }
    }

    func presentContextMenu() {
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

    func contextMenuAnchorPoint() -> NSPoint {
        guard let button = statusItem.button,
              let window = button.window else {
            return .zero
        }
        let frameInWindow = button.convert(button.bounds, to: nil)
        let screenFrame = window.convertToScreen(frameInWindow)
        return NSPoint(x: screenFrame.minX, y: screenFrame.minY - 2)
    }

    // MARK: - Expanded session sync (macOS 27+)

    func handlePanelHiddenByUserAction() {
        guard !isEndingExpandedSession else {
            return
        }
        if #available(macOS 27.0, *), let session = statusItem.expandedInterfaceSession {
            logger.statusItem("panel hidden while session active; cancelling expanded session")
            session.cancel()
        }
    }
}

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
