import Foundation
import SwiftUI

@MainActor
final class DeclarativeModule: TypedModuleContribution {
    private let package: ExternalModulePackage
    private let decoder = JSONDecoder()

    init(package: ExternalModulePackage) {
        self.package = package
    }

    var manifest: ModuleManifest {
        package.moduleManifest
    }

    func handle(
        command: Command,
        capabilities: GrantedCapabilities,
        bridge: ModuleBridge
    ) async -> DomainTransition {
        switch command {
        case .refresh:
            let snapshot = loadSnapshot()
            let envelope = ProjectionBuilder.buildEnvelope(from: snapshot)
            return DomainTransition(
                effects: [.publishSnapshot(envelope)],
                health: .healthy,
                refreshProjection: true
            )
        case .userAction(let actionID, _):
            guard let definition = package.manifest.actions.first(where: { $0.id == actionID }) else {
                return .empty
            }
            return handleAction(definition)
        default:
            return .empty
        }
    }

    func buildProjection() -> ProjectionSet {
        ProjectionBuilder.build(from: loadSnapshot())
    }

    func statusCandidates() -> [StatusCandidate] {
        let snap = loadSnapshot()
        return snap.signals.map { signal in
            StatusCandidate(
                id: signal.id,
                sourceModule: manifest.id,
                semanticRole: .primary,
                severity: signal.severity,
                priority: signal.priority,
                text: signal.title,
                icon: signal.systemImage,
                createdAt: snap.timestamp,
                expiresAt: nil,
                interruptPolicy: .normal,
                trustLevel: .unsignedLocal
            )
        }
    }

    func panelContent(context: PanelHostContext) -> some View {
        DeclarativeModulePanel(manifest: manifest, descriptor: package.manifest.panel, snapshot: loadSnapshot())
    }

    private func handleAction(_ definition: ExternalModuleActionDefinition) -> DomainTransition {
        switch definition.kind {
        case .copy:
            return DomainTransition(
                effects: [.copyToClipboard(definition.value ?? "")],
                health: nil,
                refreshProjection: false
            )
        case .openURL, .deepLink:
            guard let value = definition.value,
                  let url = URL(string: value) else {
                return .empty
            }
            return DomainTransition(
                effects: [.openURL(url)],
                health: nil,
                refreshProjection: false
            )
        case .refresh:
            return DomainTransition(
                effects: [.requestRefresh(reason: .cascade)],
                health: nil,
                refreshProjection: false
            )
        }
    }

    private func loadSnapshot() -> ModuleSnapshot {
        guard FileManager.default.fileExists(atPath: package.snapshotURL.path(percentEncoded: false)) else {
            return ModuleSnapshot(
                id: manifest.id,
                title: manifest.displayName,
                subtitle: "No snapshot.json in module package",
                systemImage: manifest.systemImage,
                freshness: .unavailable("No cached snapshot")
            )
        }

        let snapshot = try? decoder.decode(ExternalModuleSnapshot.self, from: Data(contentsOf: package.snapshotURL))
        return snapshot?.snapshot(moduleID: manifest.id, fallbackSystemImage: manifest.systemImage)
            ?? ModuleSnapshot(
                id: manifest.id,
                title: manifest.displayName,
                subtitle: "Failed to read snapshot",
                systemImage: manifest.systemImage,
                freshness: .unavailable("Snapshot decode error")
            )
    }
}
