import Foundation
import SwiftUI

@MainActor
final class CounterModule: TypedModuleContribution {
    private var count: Int
    private var stepSize: Int
    private var minValue: Int?
    private var maxValue: Int?
    private var lastModified: Date?

    private let settings: ModuleSettingsNamespace?
    private let cache: ModuleCacheNamespace?

    init(
        settings: ModuleSettingsNamespace? = nil,
        cache: ModuleCacheNamespace? = nil
    ) {
        self.settings = settings
        self.cache = cache
        let state = Self.loadState(from: settings)
        self.count = state?.count ?? 0
        self.stepSize = state?.stepSize ?? 1
        self.minValue = state?.minValue
        self.maxValue = state?.maxValue
        self.lastModified = state?.lastModified
    }

    var manifest: ModuleManifest { Self.staticManifest }

    static let staticManifest = ModuleManifest(
        id: "counter",
        displayName: "Counter",
        subtitle: "Persistent counter with adjustable step",
        systemImage: "number.circle",
        version: "1.1.0",
        author: "Wenjie Xu",
        capabilities: [.statusItem, .panel, .widgets, .actions, .cachedState, .deepLinks],
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
        case .userAction(let actionID, _):
            switch actionID {
            case "increment":
                let newValue = count + stepSize
                if let max = maxValue, newValue > max { return .empty }
                count = newValue
            case "decrement":
                let newValue = count - stepSize
                if let min = minValue, newValue < min { return .empty }
                count = newValue
            case "reset":
                count = 0
            case "setStepSize":
                guard let step = command.actionInt, step > 0 else { return .empty }
                stepSize = step
            case "setBounds":
                guard let bounds = command.actionPayloadData(CounterBounds.self) else { return .empty }
                minValue = bounds.minValue
                maxValue = bounds.maxValue
                if let minValue, count < minValue { count = minValue }
                if let maxValue, count > maxValue { count = maxValue }
            default:
                return .empty
            }
            lastModified = Date()
            persistState()
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
                semanticRole: .primary,
                severity: signal.severity,
                priority: signal.priority,
                text: signal.title,
                icon: signal.systemImage,
                createdAt: snap.timestamp,
                expiresAt: nil,
                interruptPolicy: .normal,
                trustLevel: .bundled
            )
        }
    }

    func panelContent(context: PanelHostContext) -> some View {
        let snapshot = buildSnapshot()
        return CounterPanel(
            snapshot: snapshot,
            count: Int(snapshot.metrics["count"] ?? 0),
            stepSize: Binding(
                get: { Int(snapshot.metadata["stepSize"] ?? "1") ?? 1 },
                set: { newValue in
                    context.dispatch(.userAction(actionID: "setStepSize", payload: .init(text: "\(newValue)")))
                }
            ),
            minValue: Binding(
                get: { snapshot.metadata["minValue"].flatMap(Int.init) },
                set: { newValue in
                    let currentMax = snapshot.metadata["maxValue"].flatMap(Int.init)
                    let bounds = CounterBounds(minValue: newValue, maxValue: currentMax)
                    context.dispatch(.userAction(actionID: "setBounds", payload: .init(data: try? JSONEncoder().encode(bounds))))
                }
            ),
            maxValue: Binding(
                get: { snapshot.metadata["maxValue"].flatMap(Int.init) },
                set: { newValue in
                    let currentMin = snapshot.metadata["minValue"].flatMap(Int.init)
                    let bounds = CounterBounds(minValue: currentMin, maxValue: newValue)
                    context.dispatch(.userAction(actionID: "setBounds", payload: .init(data: try? JSONEncoder().encode(bounds))))
                }
            ),
            onIncrement: { context.dispatch(.userAction(actionID: "increment", payload: nil)) },
            onDecrement: { context.dispatch(.userAction(actionID: "decrement", payload: nil)) },
            onReset: { context.dispatch(.userAction(actionID: "reset", payload: nil)) }
        )
    }

    // MARK: - Internals

    private func buildSnapshot() -> ModuleSnapshot {
        var meta: [String: String] = [
            "stepSize": "\(stepSize)"
        ]
        if let lastModified {
            meta["lastModified"] = ISO8601DateFormatter().string(from: lastModified)
        }
        if let minValue { meta["minValue"] = "\(minValue)" }
        if let maxValue { meta["maxValue"] = "\(maxValue)" }

        var signals: [StatusSignal] = []
        if let max = maxValue, count >= max {
            signals.append(StatusSignal(
                id: "counter.atMax", title: "At Maximum", message: "Counter reached upper bound of \(max).",
                systemImage: "arrow.up.to.line", severity: .warning, priority: 50
            ))
        }
        if let min = minValue, count <= min {
            signals.append(StatusSignal(
                id: "counter.atMin", title: "At Minimum", message: "Counter reached lower bound of \(min).",
                systemImage: "arrow.down.to.line", severity: .warning, priority: 50
            ))
        }

        return ModuleSnapshot(
            id: manifest.id,
            title: "\(count)",
            subtitle: lastModified.map { "Last change: \(relativeTime(from: $0))" } ?? "No changes yet",
            systemImage: manifest.systemImage,
            signals: signals,
            metrics: ["count": Double(count)],
            metadata: meta
        )
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Persistence (via capabilities, no UserDefaults.standard)

    private static let stateKey = "moduleState"

    private func persistState() {
        let state = CounterState(
            count: count, stepSize: stepSize,
            minValue: minValue, maxValue: maxValue,
            lastModified: lastModified
        )
        settings?.set(state, forKey: Self.stateKey)
    }

    private static func loadState(from settings: ModuleSettingsNamespace?) -> CounterState? {
        settings?.get(CounterState.self, forKey: stateKey)
    }
}
