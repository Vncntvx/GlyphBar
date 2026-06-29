import Foundation
import SwiftUI

/// Lightweight contribution descriptor used by the panel host to lay out
/// module panels without each module having to manage its own hosting view.
@MainActor
struct ModuleContribution {
    let moduleID: String
    let viewProvider: (PanelHostContext) -> AnyView?
}
