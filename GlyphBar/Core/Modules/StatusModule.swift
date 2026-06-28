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

struct RotationItemDescriptor: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let tooltip: String
}

@MainActor
protocol StatusModule: AnyObject {
    var manifest: ModuleManifest { get }

    func refresh(context: ModuleContext) async throws -> ModuleSnapshot
    func handle(action: ModuleAction, context: ModuleContext) async throws -> ModuleEvent
    func makePanelView(context: ModuleContext, snapshot: ModuleSnapshot?) -> AnyView
    /// Return items to display in status bar rotation. Default returns a single item from snapshot.
    func statusBarRotationItems(snapshot: ModuleSnapshot) -> [RotationItemDescriptor]
}

extension StatusModule {
    func handle(action: ModuleAction, context: ModuleContext) async throws -> ModuleEvent {
        .none
    }

    func statusBarRotationItems(snapshot: ModuleSnapshot) -> [RotationItemDescriptor] {
        [RotationItemDescriptor(
            id: "default",
            title: snapshot.title,
            systemImage: snapshot.systemImage,
            tooltip: snapshot.subtitle
        )]
    }
}
