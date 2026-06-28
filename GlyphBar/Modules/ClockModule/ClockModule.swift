import Foundation
import SwiftUI

@MainActor
final class ClockModule: StatusModule {
    private var uses24HourClock: Bool {
        didSet { persistState() }
    }
    private var showSeconds: Bool {
        didSet { persistState() }
    }
    private var worldTimezones: [String] {
        didSet { persistState() }
    }

    private let defaults = UserDefaults.standard

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

    init() {
        let state = Self.loadState()
        self.uses24HourClock = state?.uses24HourClock ?? true
        self.showSeconds = state?.showSeconds ?? false
        self.worldTimezones = state?.worldTimezones ?? []
    }

    var manifest: ModuleManifest {
        ModuleManifest(
            id: "clock",
            displayName: "Clock",
            subtitle: "Local time, date, and world clocks",
            systemImage: "clock",
            version: "1.1.0",
            author: "Wenjie Xu",
            capabilities: [.statusItem, .panel, .widgets, .actions, .deepLinks],
            permissions: [.pasteboard],
            defaultRefreshPolicy: .interval(seconds: 5),
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
    }

    func refresh(context: ModuleContext) async throws -> ModuleSnapshot {
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

    func handle(action: ModuleAction, context: ModuleContext) async throws -> ModuleEvent {
        switch action.id {
        case "copyTimestamp":
            return .copyToPasteboard(ISO8601DateFormatter().string(from: Date()))
        case "toggleFormat":
            uses24HourClock.toggle()
            return .refreshRequested(manifest.id)
        default:
            return .none
        }
    }

    func makePanelView(context: ModuleContext, snapshot: ModuleSnapshot?) -> AnyView {
        AnyView(ClockPanel(
            snapshot: snapshot,
            uses24HourClock: Binding(
                get: { [weak self] in self?.uses24HourClock ?? true },
                set: { [weak self] in
                    self?.uses24HourClock = $0
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        do {
                            let snap = try await self.refresh(context: context)
                            context.cacheStore.save(snap)
                        } catch {
                            context.logger.error("Clock refresh failed: \(error.localizedDescription)")
                        }
                    }
                }
            ),
            showSeconds: Binding(
                get: { [weak self] in self?.showSeconds ?? false },
                set: { [weak self] in
                    self?.showSeconds = $0
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        do {
                            let snap = try await self.refresh(context: context)
                            context.cacheStore.save(snap)
                        } catch {
                            context.logger.error("Clock refresh failed: \(error.localizedDescription)")
                        }
                    }
                }
            ),
            worldTimezones: Binding(
                get: { [weak self] in self?.worldTimezones ?? [] },
                set: { [weak self] in self?.worldTimezones = $0 }
            ),
            availableTimezones: Self.availableTimezones
        ))
    }

    // MARK: - Persistence

    private struct ClockState: Codable {
        let uses24HourClock: Bool
        let showSeconds: Bool
        let worldTimezones: [String]
    }

    private static let stateKey = "clock.moduleState"

    private func persistState() {
        let state = ClockState(
            uses24HourClock: uses24HourClock,
            showSeconds: showSeconds,
            worldTimezones: worldTimezones
        )
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.stateKey)
        }
    }

    private static func loadState() -> ClockState? {
        guard let data = UserDefaults.standard.data(forKey: stateKey) else { return nil }
        return try? JSONDecoder().decode(ClockState.self, from: data)
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
