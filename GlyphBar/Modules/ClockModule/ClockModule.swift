import Foundation
import SwiftUI

@MainActor
final class ClockModule: TypedModuleContribution, PresentationTickable {
    private var uses24HourClock: Bool
    private var showSeconds: Bool
    private var worldTimezones: [String]

    private let settings: ModuleSettingsNamespace?

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
                        ClockTimezoneCatalog.isAvailable(candidate)
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
            candidates.append(StatusCandidate(
                id: "clock.world.\(tzID)",
                sourceModule: manifest.id,
                semanticRole: .rotation,
                severity: .info,
                priority: 20,
                text: ClockTimezoneCatalog.label(for: tzID),
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
        // Binding setters dispatch commands; module state remains behind handle(command:).
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
            availableTimezones: ClockTimezoneCatalog.availableTimezones
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
