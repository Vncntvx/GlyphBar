import AppKit
import Combine

enum StatusItemClickAction: Equatable {
    case togglePanel
    case openContextMenu
}

struct StatusItemClickRouter {
    static func action(for eventType: NSEvent.EventType?) -> StatusItemClickAction {
        eventType == .rightMouseUp ? .openContextMenu : .togglePanel
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let runtime: ModuleRuntime
    private let settingsStore: AppSettingsStore
    private let panelCoordinator: QuickPanelCoordinator
    private let menuCoordinator: AppMenuCoordinator
    private let composer = StatusComposer()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables: Set<AnyCancellable> = []
    private var pendingRender: DispatchWorkItem?
    private var isPresentingContextMenu = false
    private var lastMouseEventType: NSEvent.EventType?
    private var eventMonitor: Any?

    init(
        runtime: ModuleRuntime,
        settingsStore: AppSettingsStore,
        panelCoordinator: QuickPanelCoordinator,
        menuCoordinator: AppMenuCoordinator
    ) {
        self.runtime = runtime
        self.settingsStore = settingsStore
        self.panelCoordinator = panelCoordinator
        self.menuCoordinator = menuCoordinator
        super.init()
    }

    func start() {
        configureButton()
        startEventMonitoring()
        observeRuntime()
        render()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "GlyphBar"
    }

    private func startEventMonitoring() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            if event.window == self?.statusItem.button?.window {
                self?.lastMouseEventType = event.type
            }
            return event
        }
    }

    private func observeRuntime() {
        runtime.$snapshots
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleRender()
            }
            .store(in: &cancellables)

        settingsStore.$primaryModuleID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleRender()
            }
            .store(in: &cancellables)
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
        let presentation = composer.compose(
            snapshots: runtime.snapshots,
            primaryModuleID: settingsStore.primaryModuleID
        )

        guard let button = statusItem.button else {
            return
        }

        button.title = settingsStore.compactStatusTitle ? "" : " \(presentation.title)"
        button.image = NSImage(
            systemSymbolName: presentation.systemImage,
            accessibilityDescription: presentation.title
        )
        button.imagePosition = .imageLeft
        button.toolTip = presentation.tooltip.isEmpty ? presentation.title : presentation.tooltip
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        switch StatusItemClickRouter.action(for: lastMouseEventType) {
        case .togglePanel:
            panelCoordinator.toggle(relativeTo: statusItem)
        case .openContextMenu:
            guard !isPresentingContextMenu else {
                return
            }
            isPresentingContextMenu = true
            defer { isPresentingContextMenu = false }

            panelCoordinator.close()
            let menu = menuCoordinator.makeMenu()

            let buttonFrameInWindow = sender.convert(sender.bounds, to: nil)
            guard let window = sender.window else { return }
            let screenFrame = window.convertToScreen(buttonFrameInWindow)
            let menuPoint = NSPoint(x: screenFrame.minX, y: screenFrame.minY - 2)
            menu.popUp(positioning: nil, at: menuPoint, in: nil)
        }
    }
}
