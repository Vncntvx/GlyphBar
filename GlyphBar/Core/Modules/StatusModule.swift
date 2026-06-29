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

    // MARK: - P1.10 mechanism B: capability registry + command dispatch

    /// Capabilities granted to the module that owns this context. Populated by
    /// `registerCapability(_:)` during module construction (P1.13). P1.10 only
    /// exposes the storage and accessor; modules still read legacy fields above.
    private var capabilities: [CapabilityKey: any Capability] = [:]

    /// Kernel command channel. Modules call this to dispatch `Command` values
    /// back to the kernel (e.g. `.requestRefresh`). P1.10 only stores the
    /// closure; P1.11 wires it to `Kernel.dispatch`.
    var dispatchCommand: ((Command) -> Void)?

    /// Returns the capability registered for `key`, cast to the requested type.
    /// Returns `nil` if no capability is registered for that key or the cast fails.
    func capability<T: Capability>(_ key: CapabilityKey) -> T? {
        capabilities[key] as? T
    }

    /// Registers a capability. `cap.declaredKey` is used as the storage key.
    /// Mutating because `ModuleContext` is a struct.
    @MainActor
    mutating func registerCapability(_ cap: any Capability) {
        capabilities[type(of: cap).declaredKey] = cap
    }
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

// MARK: - P1.11 mechanism A: Command bridge

extension StatusModule {
    /// Default `ModuleContract.handle(command:capabilities:bridge:)` implementation
    /// that bridges to the legacy `refresh(context:)` / `handle(action:context:)` methods.
    ///
    /// P1.11 minimal: this default returns `.empty` because the legacy methods
    /// require a `ModuleContext` that is not available through the new signature.
    /// Use `handle(command:capabilities:bridge:legacyContext:)` to perform the
    /// actual bridge; P1.13 wires each module to call that helper from its own
    /// `handle(command:capabilities:bridge:)` override once it captures the context.
    func handle(
        command: Command,
        capabilities: GrantedCapabilities,
        bridge: ModuleBridge
    ) async -> DomainTransition {
        .empty
    }

    /// Bridge helper that performs the actual legacy delegation when a
    /// `ModuleContext` is available. Call this from a module's
    /// `handle(command:capabilities:bridge:)` override after capturing the context.
    func handle(
        command: Command,
        capabilities: GrantedCapabilities,
        bridge: ModuleBridge,
        legacyContext: ModuleContext
    ) async -> DomainTransition {
        switch command {
        case .refresh:
            do {
                let snapshot = try await refresh(context: legacyContext)
                let envelope = ProjectionBuilder.buildEnvelope(from: snapshot)
                return DomainTransition(
                    effects: [.publishSnapshot(envelope)],
                    health: .healthy,
                    refreshProjection: true
                )
            } catch {
                return DomainTransition(
                    effects: [.showNotice(error.localizedDescription)],
                    health: .unavailable(reason: .unknown(error.localizedDescription)),
                    refreshProjection: false
                )
            }
        case .userAction(let actionID, let payload):
            let action = ModuleAction(id: actionID, title: actionID, systemImage: "")
            do {
                let event = try await handle(action: action, context: legacyContext)
                return Self.transition(from: event)
            } catch {
                return DomainTransition(
                    effects: [.showNotice(error.localizedDescription)],
                    health: nil,
                    refreshProjection: false
                )
            }
        default:
            return .empty
        }
    }

    /// Convert a legacy `ModuleEvent` to a `DomainTransition` with equivalent effects.
    static func transition(from event: ModuleEvent) -> DomainTransition {
        switch event {
        case .none:
            return .empty
        case .didUpdateSnapshot(let snapshot):
            let envelope = ProjectionBuilder.buildEnvelope(from: snapshot)
            return DomainTransition(
                effects: [.publishSnapshot(envelope)],
                health: nil,
                refreshProjection: true
            )
        case .copyToPasteboard(let value):
            return DomainTransition(
                effects: [.copyToClipboard(value)],
                health: nil,
                refreshProjection: false
            )
        case .refreshRequested, .stateChanged:
            return DomainTransition(
                effects: [.requestRefresh(reason: .cascade)],
                health: nil,
                refreshProjection: false
            )
        case .userNotice(let message):
            return DomainTransition(
                effects: [.showNotice(message)],
                health: nil,
                refreshProjection: false
            )
        case .openSettings:
            return DomainTransition(
                effects: [.openModuleSettings],
                health: nil,
                refreshProjection: false
            )
        }
    }
}
