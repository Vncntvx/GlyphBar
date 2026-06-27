import Foundation
import SwiftUI

@MainActor
final class CounterModule: StatusModule {
    private var count = 0

    var manifest: ModuleManifest {
        ModuleManifest(
            id: "counter",
            displayName: "Counter",
            subtitle: "Shared action state",
            systemImage: "number.circle",
            capabilities: [.statusItem, .panel, .widgets, .actions, .cachedState],
            permissions: [],
            defaultRefreshPolicy: .manual,
            actions: [
                ModuleAction(id: "increment", title: "Increment", systemImage: "plus"),
                ModuleAction(id: "decrement", title: "Decrement", systemImage: "minus"),
                ModuleAction(id: "reset", title: "Reset", systemImage: "arrow.counterclockwise", role: .destructive)
            ],
            widgets: [
                ModuleWidgetDescriptor(
                    id: "counter.value",
                    title: "Counter",
                    subtitle: "Current count",
                    systemImage: "number.circle",
                    supportedFamilies: ["small", "medium", "large"]
                )
            ]
        )
    }

    func refresh(context: ModuleContext) async throws -> ModuleSnapshot {
        ModuleSnapshot(
            id: manifest.id,
            title: "\(count)",
            subtitle: "Current counter value",
            systemImage: manifest.systemImage,
            metrics: ["count": Double(count)]
        )
    }

    func handle(action: ModuleAction, context: ModuleContext) async throws -> ModuleEvent {
        switch action.id {
        case "increment":
            count += 1
        case "decrement":
            count -= 1
        case "reset":
            count = 0
        default:
            return .none
        }
        return .didUpdateSnapshot(try await refresh(context: context))
    }

    func makePanelView(context: ModuleContext, snapshot: ModuleSnapshot?) -> AnyView {
        AnyView(CounterPanel(snapshot: snapshot))
    }
}

private struct CounterPanel: View {
    let snapshot: ModuleSnapshot?

    var body: some View {
        GlyphSurface {
            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot?.title ?? "0")
                    .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                Text(snapshot?.subtitle ?? "Use actions below to change the value.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
