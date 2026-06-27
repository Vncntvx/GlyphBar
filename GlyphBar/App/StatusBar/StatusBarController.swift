import AppKit
import Combine

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
        guard let event = NSApp.currentEvent else {
            panelCoordinator.toggle(relativeTo: statusItem)
            return
        }

        if event.type == .rightMouseUp {
            statusItem.menu = menuCoordinator.makeMenu()
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            panelCoordinator.toggle(relativeTo: statusItem)
        }
    }
}
