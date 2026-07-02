import Foundation
import SwiftUI

@MainActor
final class NetworkMockModule: TypedModuleContribution {
    private let statusProvider: NetworkStatusProvider

    init(statusProvider: NetworkStatusProvider? = nil) {
        self.statusProvider = statusProvider ?? NetworkStatusProvider()
    }

    var manifest: ModuleManifest { Self.staticManifest }

    static let staticManifest = ModuleManifest(
        id: "networkMock",
        displayName: "Network",
        subtitle: "Connection status and interface info",
        systemImage: "antenna.radiowaves.left.and.right",
        version: "1.1.0",
        author: "Wenjie Xu",
        capabilities: [.statusItem, .panel, .widgets, .actions, .cachedState, .deepLinks],
        permissions: [],
        defaultRefreshPolicy: .interval(seconds: 30),
        actions: [
            ModuleAction(id: "retry", title: "Refresh", systemImage: "arrow.clockwise", role: .refresh),
            ModuleAction(id: "copyIP", title: "Copy IP", systemImage: "doc.on.doc")
        ],
        widgets: [
            ModuleWidgetDescriptor(
                id: "networkMock.state",
                title: "Network",
                subtitle: "Connection status",
                systemImage: "antenna.radiowaves.left.and.right",
                supportedFamilies: ["small", "medium", "large"]
            )
        ]
    )

    // MARK: - TypedModuleContribution

    func handle(
        command: Command,
        capabilities: GrantedCapabilities,
        bridge: ModuleBridge
    ) async -> DomainTransition {
        switch command {
        case .refresh:
            do {
                let snap = try await statusProvider.refresh(
                    moduleID: manifest.id,
                    systemImage: manifest.systemImage
                )
                return DomainTransition(
                    effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: snap))],
                    health: .healthy,
                    refreshProjection: true
                )
            } catch {
                return DomainTransition(
                    effects: [.showNotice(error.localizedDescription)],
                    health: .degraded(reason: .networkError(error.localizedDescription)),
                    refreshProjection: false
                )
            }
        case .userAction(let actionID, _):
            if actionID == "copyIP", let ip = statusProvider.localIPAddress() {
                return DomainTransition(
                    effects: [.copyToClipboard(ip)],
                    health: nil,
                    refreshProjection: false
                )
            }
            return .empty
        default:
            return .empty
        }
    }

    func buildProjection() -> ProjectionSet {
        ProjectionBuilder.build(from: statusProvider.realSnapshot(moduleID: manifest.id))
    }

    func statusCandidates() -> [StatusCandidate] {
        let snap = statusProvider.realSnapshot(moduleID: manifest.id)
        return snap.signals.map { signal in
            StatusCandidate(
                id: signal.id,
                sourceModule: manifest.id,
                semanticRole: .alert,
                severity: signal.severity,
                priority: signal.priority,
                text: signal.title,
                icon: signal.systemImage,
                createdAt: snap.timestamp,
                expiresAt: nil,
                interruptPolicy: .preempt,
                trustLevel: .bundled
            )
        }
    }

    func panelContent(context: PanelHostContext) -> some View {
        NetworkPanel(
            snapshot: statusProvider.realSnapshot(moduleID: manifest.id),
            localIPAddress: statusProvider.localIPAddress(),
            useMockMode: Binding(
                get: { [statusProvider] in statusProvider.useMockMode },
                set: { [statusProvider] in
                    statusProvider.useMockMode = $0
                    context.dispatch(.refresh(reason: .manual))
                }
            )
        )
    }
}
