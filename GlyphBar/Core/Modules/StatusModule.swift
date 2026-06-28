import Foundation
import SwiftUI

struct ModuleContext {
    let logger: GlyphLogger
    let cacheStore: CacheStore
    let secureStore: SecureStore
    let permissionCenter: PermissionCenter
    let settingsStore: AppSettingsStore
    let platformActions: PlatformActions
    let widgetBridge: WidgetDataBridge
    /// Called by modules to publish updated snapshots to the status bar / widgets.
    var publishSnapshot: ((ModuleSnapshot) -> Void)?
}

@MainActor
protocol StatusModule: AnyObject {
    var manifest: ModuleManifest { get }

    func refresh(context: ModuleContext) async throws -> ModuleSnapshot
    func handle(action: ModuleAction, context: ModuleContext) async throws -> ModuleEvent
    func makePanelView(context: ModuleContext, snapshot: ModuleSnapshot?) -> AnyView
}

extension StatusModule {
    func handle(action: ModuleAction, context: ModuleContext) async throws -> ModuleEvent {
        .none
    }
}
