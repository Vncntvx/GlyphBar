import Foundation

/// Context handed to a module when rendering its panel. Modules dispatch
/// commands back to the kernel via `dispatch(_:)` instead of capturing the
/// runtime directly.
@MainActor
final class PanelHostContext {
    let moduleID: String
    private let dispatch: (Command) -> Void

    init(moduleID: String, dispatch: @escaping (Command) -> Void) {
        self.moduleID = moduleID
        self.dispatch = dispatch
    }

    func dispatch(_ command: Command) {
        dispatch(command)
    }
}
