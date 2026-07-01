import Foundation
import SwiftUI

@MainActor
final class CounterModule: TypedModuleContribution {
    private var count: Int
    private var stepSize: Int
    private var minValue: Int?
    private var maxValue: Int?
    private var lastModified: Date?

    // P1.13: capabilities injected at init time (no UserDefaults.standard).
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
        CounterPanel(
            snapshot: buildSnapshot(),
            count: count,
            stepSize: Binding(
                get: { [weak self] in self?.stepSize ?? 1 },
                set: { newValue in
                    context.dispatch(.userAction(actionID: "setStepSize", payload: .init(text: "\(newValue)")))
                }
            ),
            minValue: Binding(
                get: { [weak self] in self?.minValue },
                set: { [weak self] newValue in
                    let bounds = CounterBounds(minValue: newValue, maxValue: self?.maxValue)
                    context.dispatch(.userAction(actionID: "setBounds", payload: .init(data: try? JSONEncoder().encode(bounds))))
                }
            ),
            maxValue: Binding(
                get: { [weak self] in self?.maxValue },
                set: { [weak self] newValue in
                    let bounds = CounterBounds(minValue: self?.minValue, maxValue: newValue)
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

    private struct CounterState: Codable {
        let count: Int
        let stepSize: Int
        let minValue: Int?
        let maxValue: Int?
        let lastModified: Date?
    }

    private static let stateKey = "moduleState"

    private struct CounterBounds: Codable {
        var minValue: Int?
        var maxValue: Int?
    }

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

private extension Command {
    var actionInt: Int? {
        guard case .userAction(_, let payload) = self,
              let text = payload?.text else {
            return nil
        }
        return Int(text)
    }

    func actionPayloadData<T: Decodable>(_ type: T.Type) -> T? {
        guard case .userAction(_, let payload) = self,
              let data = payload?.data else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}

private struct CounterPanel: View {
    let snapshot: ModuleSnapshot?
    let count: Int
    @Binding var stepSize: Int
    @Binding var minValue: Int?
    @Binding var maxValue: Int?
    var onIncrement: () -> Void
    var onDecrement: () -> Void
    var onReset: () -> Void

    @State private var showResetConfirmation = false
    @State private var showBoundsEditor = false
    @State private var minText: String = ""
    @State private var maxText: String = ""

    private let stepOptions = [1, 5, 10, 100]

    var body: some View {
        VStack(spacing: 20) {
                // Large count with color
                Text("\(count)")
                    .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(countColor)
                    .contentTransition(.numericText())

                // Subtitle
                if let subtitle = snapshot?.subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // +/- Buttons
                HStack(spacing: 24) {
                    Button(action: onDecrement) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 44))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .disabled(boundReached(direction: -1))
                    .opacity(boundReached(direction: -1) ? 0.35 : 1)

                    Button(action: onReset) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 30))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(count == 0 ? 0.35 : 1)
                    .disabled(count == 0)

                    Button(action: onIncrement) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .disabled(boundReached(direction: 1))
                    .opacity(boundReached(direction: 1) ? 0.35 : 1)
                }

                // Step size selector
                HStack(spacing: 4) {
                    Text("Step:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Step", selection: $stepSize) {
                        ForEach(stepOptions, id: \.self) { step in
                            Text("±\(step)").tag(step)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 200)
                }

                // Bounds
                DisclosureGroup("Bounds", isExpanded: $showBoundsEditor) {
                    HStack(spacing: 8) {
                        TextField("Min", text: $minText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .onSubmit { applyBounds() }
                        Text("–")
                            .foregroundStyle(.secondary)
                        TextField("Max", text: $maxText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .onSubmit { applyBounds() }
                        Button("Set") { applyBounds() }
                            .controlSize(.small)
                        if minValue != nil || maxValue != nil {
                            Button("Clear") {
                                minValue = nil
                                maxValue = nil
                                minText = ""
                                maxText = ""
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
                .onAppear {
                    minText = minValue.map(String.init) ?? ""
                    maxText = maxValue.map(String.init) ?? ""
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(14)
    }

    private var countColor: Color {
        if count > 0 { return .green }
        if count < 0 { return .red }
        return .primary
    }

    private func boundReached(direction: Int) -> Bool {
        if direction > 0, let max = maxValue, count >= max { return true }
        if direction < 0, let min = minValue, count <= min { return true }
        return false
    }

    private func applyBounds() {
        minValue = Int(minText)
        maxValue = Int(maxText)
        if minValue == nil { minText = "" }
        if maxValue == nil { maxText = "" }
    }
}
