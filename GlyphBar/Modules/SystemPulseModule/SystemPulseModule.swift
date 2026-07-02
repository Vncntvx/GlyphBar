import Foundation
import SwiftUI

@MainActor
final class SystemPulseModule: TypedModuleContribution {
    private let snapshotProvider: SystemPulseSnapshotProvider

    init(systemMetrics: SystemMetricsCapability? = nil) {
        self.snapshotProvider = SystemPulseSnapshotProvider(systemMetrics: systemMetrics)
    }

    var manifest: ModuleManifest { Self.staticManifest }

    static let staticManifest = ModuleManifest(
        id: "systemPulse",
        displayName: "System Pulse",
        subtitle: "Real-time CPU, memory, storage, and battery",
        systemImage: "waveform.path.ecg",
        version: "1.1.0",
        author: "Wenjie Xu",
        capabilities: [.statusItem, .panel, .widgets, .actions, .deepLinks],
        permissions: [.systemMetrics],
        defaultRefreshPolicy: .interval(seconds: 5),
        actions: [
            ModuleAction(id: "refresh", title: "Refresh", systemImage: "arrow.clockwise", role: .refresh)
        ],
        widgets: [
            ModuleWidgetDescriptor(
                id: "systemPulse.metrics",
                title: "System Pulse",
                subtitle: "System metrics",
                systemImage: "waveform.path.ecg",
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
            return DomainTransition(
                effects: [.publishSnapshot(ProjectionBuilder.buildEnvelope(from: buildSnapshot()))],
                health: .healthy,
                refreshProjection: true
            )
        default:
            return .empty
        }
    }

    func buildProjection() -> ProjectionSet {
        ProjectionBuilder.build(from: buildSnapshot())
    }

    func statusCandidates() -> [StatusCandidate] {
        let snap = buildSnapshot()
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
        SystemPulsePanel(snapshot: buildSnapshot())
    }

    // MARK: - Internals

    private func buildSnapshot() -> ModuleSnapshot {
        snapshotProvider.buildSnapshot(moduleID: manifest.id, systemImage: manifest.systemImage)
    }
}
