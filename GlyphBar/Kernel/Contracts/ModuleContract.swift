import Foundation
import SwiftUI

/// The kernel-level contract every module must satisfy. P1 modules still
/// conform to the legacy `StatusModule` protocol; P1.13 migrates them to
/// `ModuleContract` / `TypedModuleContribution`.
@MainActor
protocol ModuleContract: AnyObject {
    var manifest: ModuleManifest { get }

    func handle(
        command: Command,
        capabilities: GrantedCapabilities,
        bridge: ModuleBridge
    ) async -> DomainTransition

    func buildProjection() -> ProjectionSet
    func statusCandidates() -> [StatusCandidate]

    @ViewBuilder
    func panelContribution(context: PanelHostContext) -> AnyView?
}

/// Typed counterpart to `ModuleContract` for built-in modules that want to
/// return a concrete SwiftUI view from `panelContent` (no `AnyView` erasure
/// in the module's own code).
@MainActor
protocol TypedModuleContribution: ModuleContract {
    associatedtype Body: View

    @ViewBuilder
    func panelContent(context: PanelHostContext) -> Body
}

extension TypedModuleContribution {
    @ViewBuilder
    func panelContribution(context: PanelHostContext) -> AnyView? {
        AnyView(panelContent(context: context))
    }
}
