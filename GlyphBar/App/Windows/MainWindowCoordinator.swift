import AppKit

@MainActor
final class MainWindowCoordinator {
    private let platformActions: PlatformActions

    init(platformActions: PlatformActions) {
        self.platformActions = platformActions
    }

    func openLogsWindow() {
        platformActions.showSettingsWindow()
    }
}
