import Foundation
import SwiftUI

@MainActor
final class ClockModule: TypedModuleContribution, PresentationTickable {
    private var uses24HourClock: Bool
    private var showSeconds: Bool
    private var worldTimezones: [String]

    // P1.13: settings via capability (no UserDefaults.standard).
    private let settings: ModuleSettingsNamespace?

    private static let availableTimezones: [(id: String, label: String)] = [
        ("Asia/Shanghai", "Beijing"),
        ("Asia/Tokyo", "Tokyo"),
        ("Europe/London", "London"),
        ("America/New_York", "New York"),
        ("America/Los_Angeles", "Los Angeles"),
        ("Europe/Berlin", "Berlin"),
        ("Asia/Dubai", "Dubai"),
        ("Pacific/Auckland", "Auckland"),
    ]

    init(settings: ModuleSettingsNamespace? = nil) {
        self.settings = settings
        let state = Self.loadState(from: settings)
        self.uses24HourClock = state?.uses24HourClock ?? true
        self.showSeconds = state?.showSeconds ?? false
        self.worldTimezones = state?.worldTimezones ?? []
    }

    var manifest: ModuleManifest { Self.staticManifest }

    static let staticManifest = ModuleManifest(
        id: "clock",
        displayName: "Clock",
        subtitle: "Local time, date, and world clocks",
        systemImage: "clock",
        version: "1.1.0",
        author: "Wenjie Xu",
        capabilities: [.statusItem, .panel, .widgets, .actions, .deepLinks],
        permissions: [.pasteboard],
        defaultRefreshPolicy: .manual,  // P2: tick与refresh分离，Clock不再5s自动refresh
        actions: [
            ModuleAction(id: "copyTimestamp", title: "Copy Timestamp", systemImage: "doc.on.doc"),
            ModuleAction(id: "toggleFormat", title: "Toggle Format", systemImage: "clock.arrow.circlepath")
        ],
        widgets: [
            ModuleWidgetDescriptor(
                id: "clock.time",
                title: "Clock",
                subtitle: "Current local time",
                systemImage: "clock",
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
            case "copyTimestamp":
                let timestamp = ISO8601DateFormatter().string(from: Date())
                return DomainTransition(
                    effects: [
                        .publishSnapshot(ProjectionBuilder.buildEnvelope(from: buildSnapshot())),
                        .copyToClipboard(timestamp)
                    ],
                    health: .healthy,
                    refreshProjection: true
                )
            case "toggleFormat":
                uses24HourClock.toggle()
                persistState()
            case "setFormat24h":
                uses24HourClock = command.actionBool(default: uses24HourClock)
                persistState()
            case "setShowSeconds":
                showSeconds = command.actionBool(default: showSeconds)
                persistState()
            case "setWorldTimezones":
                if let zones = command.actionPayloadData([String].self) {
                    worldTimezones = zones.filter { candidate in
                        Self.availableTimezones.contains { $0.id == candidate }
                    }
                    persistState()
                }
            default:
                return .empty
            }
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
        let now = Date()
        // P2: Clock submits a primary candidate (local time) plus rotation
        // candidates (world clocks). The primary candidate is updated by
        // presentationTick, not by refresh.
        let timeFormatter = DateFormatter()
        timeFormatter.locale = .current
        timeFormatter.setLocalizedDateFormatFromTemplate(
            uses24HourClock ? (showSeconds ? "HHmmss" : "HHmm") : (showSeconds ? "hmmssa" : "hmma")
        )

        var candidates: [StatusCandidate] = [
            StatusCandidate(
                id: "clock.primary",
                sourceModule: manifest.id,
                semanticRole: .primary,
                severity: .normal,
                priority: 50,
                text: timeFormatter.string(from: now),
                icon: "clock",
                createdAt: now,
                expiresAt: nil,
                interruptPolicy: .normal,
                trustLevel: .bundled
            )
        ]

        // World clocks produce rotation candidates
        for tzID in worldTimezones {
            let label = Self.availableTimezones.first(where: { $0.id == tzID })?.label ?? tzID
            candidates.append(StatusCandidate(
                id: "clock.world.\(tzID)",
                sourceModule: manifest.id,
                semanticRole: .rotation,
                severity: .info,
                priority: 20,
                text: label,
                icon: "globe",
                createdAt: now,
                expiresAt: nil,
                interruptPolicy: .normal,
                trustLevel: .bundled
            ))
        }
        return candidates
    }

    // MARK: - PresentationTickable (P2)

    func presentationTick(trigger: PresentationTrigger, projection: ProjectionSet) -> ProjectionSet {
        // Update the primary candidate text with the current time.
        // This is a pure computation — no side effects.
        let now = Date()
        let timeFormatter = DateFormatter()
        timeFormatter.locale = .current
        timeFormatter.setLocalizedDateFormatFromTemplate(
            uses24HourClock ? (showSeconds ? "HHmmss" : "HHmm") : (showSeconds ? "hmmssa" : "hmma")
        )

        var updated = projection
        updated.statusCandidates = updated.statusCandidates.map { candidate in
            if candidate.id == "clock.primary" {
                return StatusCandidate(
                    id: candidate.id,
                    sourceModule: candidate.sourceModule,
                    semanticRole: candidate.semanticRole,
                    severity: candidate.severity,
                    priority: candidate.priority,
                    text: timeFormatter.string(from: now),
                    icon: candidate.icon,
                    createdAt: now,
                    expiresAt: candidate.expiresAt,
                    interruptPolicy: candidate.interruptPolicy,
                    trustLevel: candidate.trustLevel
                )
            }
            return candidate
        }
        return updated
    }

    func panelContent(context: PanelHostContext) -> some View {
        // P1.13 mechanism D: Binding(set:) dispatches Command instead of
        // Task { refresh; cacheStore.save }.
        ClockPanel(
            snapshot: buildSnapshot(),
            uses24HourClock: Binding(
                get: { [weak self] in self?.uses24HourClock ?? true },
                set: { newValue in
                    context.dispatch(.userAction(
                        actionID: "setFormat24h",
                        payload: .init(text: newValue ? "true" : "false")
                    ))
                }
            ),
            showSeconds: Binding(
                get: { [weak self] in self?.showSeconds ?? false },
                set: { newValue in
                    context.dispatch(.userAction(
                        actionID: "setShowSeconds",
                        payload: .init(text: newValue ? "true" : "false")
                    ))
                }
            ),
            worldTimezones: Binding(
                get: { [weak self] in self?.worldTimezones ?? [] },
                set: { newValue in
                    let data = try? JSONEncoder().encode(newValue)
                    context.dispatch(.userAction(
                        actionID: "setWorldTimezones",
                        payload: .init(data: data)
                    ))
                }
            ),
            availableTimezones: Self.availableTimezones
        )
    }

    // MARK: - Internals

    private func buildSnapshot() -> ModuleSnapshot {
        let now = Date()
        let tz = TimeZone.current

        let timeFormatter = DateFormatter()
        timeFormatter.locale = .current
        timeFormatter.setLocalizedDateFormatFromTemplate(
            uses24HourClock ? (showSeconds ? "HHmmss" : "HHmm") : (showSeconds ? "hmmssa" : "hmma")
        )

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .none

        let tzName = tz.abbreviation(for: now) ?? tz.identifier
        let offset = Double(tz.secondsFromGMT()) / 3600

        var signals: [StatusSignal] = []
        if worldTimezones.count > 2 {
            signals.append(StatusSignal(
                id: "clock.worldClocks", title: "\(worldTimezones.count) clocks",
                message: "\(worldTimezones.count) world clocks active",
                systemImage: "globe", severity: .info, priority: 20
            ))
        }

        return ModuleSnapshot(
            id: manifest.id,
            title: timeFormatter.string(from: now),
            subtitle: dateFormatter.string(from: now),
            systemImage: manifest.systemImage,
            signals: signals,
            metrics: ["offset": offset],
            metadata: [
                "timezone": tz.identifier,
                "tzAbbreviation": tzName,
                "format": uses24HourClock ? "24-hour" : "12-hour",
                "showSeconds": showSeconds ? "true" : "false"
            ]
        )
    }

    // MARK: - Persistence (via capability)

    private struct ClockState: Codable {
        let uses24HourClock: Bool
        let showSeconds: Bool
        let worldTimezones: [String]
    }

    private static let stateKey = "moduleState"

    private func persistState() {
        let state = ClockState(
            uses24HourClock: uses24HourClock,
            showSeconds: showSeconds,
            worldTimezones: worldTimezones
        )
        settings?.set(state, forKey: Self.stateKey)
    }

    private static func loadState(from settings: ModuleSettingsNamespace?) -> ClockState? {
        settings?.get(ClockState.self, forKey: stateKey)
    }
}

private extension Command {
    func actionBool(default defaultValue: Bool) -> Bool {
        guard case .userAction(_, let payload) = self,
              let text = payload?.text?.lowercased() else {
            return defaultValue
        }
        if ["true", "1", "yes"].contains(text) { return true }
        if ["false", "0", "no"].contains(text) { return false }
        return defaultValue
    }

    func actionPayloadData<T: Decodable>(_ type: T.Type) -> T? {
        guard case .userAction(_, let payload) = self,
              let data = payload?.data else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}

private struct ClockPanel: View {
    let snapshot: ModuleSnapshot?
    @Binding var uses24HourClock: Bool
    @Binding var showSeconds: Bool
    @Binding var worldTimezones: [String]
    let availableTimezones: [(id: String, label: String)]

    @State private var showTimezonePicker = false

    var body: some View {
        VStack(spacing: 20) {
            // Local time display
            VStack(spacing: 4) {
                    Text(snapshot?.title ?? "--:--")
                        .font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(snapshot?.subtitle ?? "Loading…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Timezone + offset
                if let tz = snapshot?.metadata["tzAbbreviation"] {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption)
                        Text(tz)
                            .font(.caption.weight(.medium))
                        if let offset = snapshot?.metrics["offset"] {
                            Text(String(format: "UTC%+.0f", offset))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(.thinMaterial, in: Capsule())
                }

                // Format controls
                HStack(spacing: 12) {
                    Toggle(isOn: $uses24HourClock) {
                        Label("24h", systemImage: "textformat.123")
                            .labelStyle(.iconOnly)
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)

                    Toggle(isOn: $showSeconds) {
                        Label("Seconds", systemImage: "stopwatch")
                            .labelStyle(.iconOnly)
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                }

                // World clocks
                if !worldTimezones.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("World Clocks", systemImage: "globe")
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Button {
                                showTimezonePicker.toggle()
                            } label: {
                                Image(systemName: showTimezonePicker ? "chevron.up" : "plus")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(worldTimezones, id: \.self) { tzID in
                            WorldClockRow(
                                timezoneID: tzID,
                                label: availableTimezones.first(where: { $0.id == tzID })?.label ?? tzID,
                                uses24HourClock: uses24HourClock,
                                onRemove: {
                                    worldTimezones.removeAll { $0 == tzID }
                                }
                            )
                        }
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }

                if showTimezonePicker {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add Timezone")
                            .font(.caption.weight(.semibold))
                        ForEach(availableTimezones, id: \.id) { tz in
                            if !worldTimezones.contains(tz.id) {
                                Button {
                                    worldTimezones.append(tz.id)
                                    showTimezonePicker = false
                                } label: {
                                    HStack {
                                        Text(tz.label)
                                        Spacer()
                                        Text(worldTimeText(for: tz.id))
                                            .foregroundStyle(.secondary)
                                            .font(.caption.monospacedDigit())
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(14)
    }

    private func worldTimeText(for tzID: String) -> String {
        guard let tz = TimeZone(identifier: tzID) else { return "--:--" }
        let fmt = DateFormatter()
        fmt.timeZone = tz
        fmt.setLocalizedDateFormatFromTemplate(uses24HourClock ? "HHmm" : "hmma")
        return fmt.string(from: Date())
    }
}

private struct WorldClockRow: View {
    let timezoneID: String
    let label: String
    let uses24HourClock: Bool
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .frame(width: 6, height: 6)
                .foregroundStyle(.green)
            Text(label)
                .font(.callout)
            Spacer()
            Text(timeText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var timeText: String {
        guard let tz = TimeZone(identifier: timezoneID) else { return "--:--" }
        let fmt = DateFormatter()
        fmt.timeZone = tz
        fmt.setLocalizedDateFormatFromTemplate(uses24HourClock ? "HHmm" : "hmma")
        return fmt.string(from: Date())
    }
}
