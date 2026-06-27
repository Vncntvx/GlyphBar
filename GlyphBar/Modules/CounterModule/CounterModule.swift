import Foundation
import SwiftUI

@MainActor
final class CounterModule: StatusModule {
    private var count: Int {
        didSet { persistState() }
    }
    private var stepSize: Int {
        didSet { persistState() }
    }
    private var minValue: Int? {
        didSet { persistState() }
    }
    private var maxValue: Int? {
        didSet { persistState() }
    }
    private var lastModified: Date? {
        didSet { persistState() }
    }

    private let defaults = UserDefaults.standard

    init() {
        self.count = Self.loadState()?.count ?? 0
        self.stepSize = Self.loadState()?.stepSize ?? 1
        self.minValue = Self.loadState()?.minValue
        self.maxValue = Self.loadState()?.maxValue
        self.lastModified = Self.loadState()?.lastModified
    }

    var manifest: ModuleManifest {
        ModuleManifest(
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
    }

    func refresh(context: ModuleContext) async throws -> ModuleSnapshot {
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

    func handle(action: ModuleAction, context: ModuleContext) async throws -> ModuleEvent {
        switch action.id {
        case "increment":
            let newValue = count + stepSize
            if let max = maxValue, newValue > max { return .none }
            count = newValue
        case "decrement":
            let newValue = count - stepSize
            if let min = minValue, newValue < min { return .none }
            count = newValue
        case "reset":
            count = 0
        default:
            return .none
        }
        lastModified = Date()
        return .didUpdateSnapshot(try await refresh(context: context))
    }

    func makePanelView(context: ModuleContext, snapshot: ModuleSnapshot?) -> AnyView {
        AnyView(CounterPanel(
            snapshot: snapshot,
            count: count,
            stepSize: Binding(
                get: { [weak self] in self?.stepSize ?? 1 },
                set: { [weak self] in self?.stepSize = $0; self?.persistState() }
            ),
            minValue: Binding(
                get: { [weak self] in self?.minValue },
                set: { [weak self] in self?.minValue = $0; self?.persistState() }
            ),
            maxValue: Binding(
                get: { [weak self] in self?.maxValue },
                set: { [weak self] in self?.maxValue = $0; self?.persistState() }
            ),
            onIncrement: { [weak self] in self?.adjust(by: 1, context: context) },
            onDecrement: { [weak self] in self?.adjust(by: -1, context: context) },
            onReset: { [weak self] in self?.resetCounter(context: context) }
        ))
    }

    private func adjust(by direction: Int, context: ModuleContext) {
        let newValue = count + (direction * stepSize)
        if let max = maxValue, direction > 0, newValue > max { return }
        if let min = minValue, direction < 0, newValue < min { return }
        count = newValue
        lastModified = Date()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snap = try await self.refresh(context: context)
                context.cacheStore.save(snap)
            } catch {
                context.logger.error("Counter refresh failed: \(error.localizedDescription)")
            }
        }
    }

    private func resetCounter(context: ModuleContext) {
        count = 0
        lastModified = Date()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snap = try await self.refresh(context: context)
                context.cacheStore.save(snap)
            } catch {
                context.logger.error("Counter reset refresh failed: \(error.localizedDescription)")
            }
        }
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Persistence

    private struct CounterState: Codable {
        let count: Int
        let stepSize: Int
        let minValue: Int?
        let maxValue: Int?
        let lastModified: Date?
    }

    private static let stateKey = "counter.moduleState"

    private func persistState() {
        let state = CounterState(
            count: count, stepSize: stepSize,
            minValue: minValue, maxValue: maxValue,
            lastModified: lastModified
        )
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.stateKey)
        }
    }

    private static func loadState() -> CounterState? {
        guard let data = UserDefaults.standard.data(forKey: stateKey) else { return nil }
        return try? JSONDecoder().decode(CounterState.self, from: data)
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
        GlyphSurface {
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
        }
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
