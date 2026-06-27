import Foundation
import SwiftUI

@MainActor
final class NetworkMockModule: StatusModule {
    private var forcedResults: [Bool]
    private var successCount = 0

    init(forcedResults: [Bool] = []) {
        self.forcedResults = forcedResults
    }

    var manifest: ModuleManifest {
        ModuleManifest(
            id: "networkMock",
            displayName: "Network Mock",
            subtitle: "Async refresh, failure, and stale-cache demo",
            systemImage: "antenna.radiowaves.left.and.right",
            capabilities: [.statusItem, .panel, .widgets, .actions, .cachedState],
            permissions: [],
            defaultRefreshPolicy: .interval(seconds: 120),
            actions: [
                ModuleAction(id: "retry", title: "Retry", systemImage: "arrow.clockwise", role: .refresh)
            ],
            widgets: [
                ModuleWidgetDescriptor(
                    id: "networkMock.state",
                    title: "Network Mock",
                    subtitle: "Latest async state",
                    systemImage: "antenna.radiowaves.left.and.right",
                    supportedFamilies: ["small", "medium", "large"]
                )
            ]
        )
    }

    func refresh(context: ModuleContext) async throws -> ModuleSnapshot {
        try await Task.sleep(nanoseconds: 250_000_000)

        let succeeds: Bool
        if forcedResults.isEmpty {
            succeeds = Int.random(in: 0..<100) >= 35
        } else {
            succeeds = forcedResults.removeFirst()
        }

        guard succeeds else {
            throw URLError(.timedOut)
        }

        successCount += 1
        return ModuleSnapshot(
            id: manifest.id,
            title: "Online",
            subtitle: "Last mock request succeeded",
            systemImage: manifest.systemImage,
            metrics: ["successes": Double(successCount)],
            metadata: ["request": UUID().uuidString]
        )
    }

    func handle(action: ModuleAction, context: ModuleContext) async throws -> ModuleEvent {
        action.id == "retry" ? .refreshRequested(manifest.id) : .none
    }

    func makePanelView(context: ModuleContext, snapshot: ModuleSnapshot?) -> AnyView {
        AnyView(NetworkMockPanel(snapshot: snapshot))
    }
}

private struct NetworkMockPanel: View {
    let snapshot: ModuleSnapshot?

    var body: some View {
        switch snapshot?.freshness {
        case .unavailable(let reason):
            GlyphCard {
                Label(reason, systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.red)
            }
        default:
            VStack(alignment: .leading, spacing: 12) {
                GlyphMetricCard(
                    title: "Successful Requests",
                    value: "\(Int(snapshot?.metrics["successes"] ?? 0))",
                    systemImage: "checkmark.circle"
                )
                if let request = snapshot?.metadata["request"] {
                    GlyphCard {
                        Text(request)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
