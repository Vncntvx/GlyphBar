import Foundation
import SwiftUI

@MainActor
final class ClockModule: StatusModule {
    private var uses24HourClock = true

    var manifest: ModuleManifest {
        ModuleManifest(
            id: "clock",
            displayName: "Clock",
            subtitle: "Local time, date, and timezone",
            systemImage: "clock",
            capabilities: [.statusItem, .panel, .widgets, .actions],
            permissions: [.pasteboard],
            defaultRefreshPolicy: .interval(seconds: 60),
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
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .medium
        timeFormatter.dateStyle = .none
        timeFormatter.locale = .current
        timeFormatter.setLocalizedDateFormatFromTemplate(uses24HourClock ? "HHmmss" : "hmmssa")

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .none

        let timezone = TimeZone.current.identifier
        return ModuleSnapshot(
            id: manifest.id,
            title: timeFormatter.string(from: now),
            subtitle: dateFormatter.string(from: now),
            systemImage: manifest.systemImage,
            metrics: ["offset": Double(TimeZone.current.secondsFromGMT()) / 3600],
            metadata: ["timezone": timezone, "format": uses24HourClock ? "24-hour" : "12-hour"]
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
        AnyView(ClockPanel(snapshot: snapshot))
    }
}

private struct ClockPanel: View {
    let snapshot: ModuleSnapshot?

    var body: some View {
        GlyphSurface {
            VStack(alignment: .leading, spacing: 16) {
                Text(snapshot?.title ?? "--:--")
                    .font(.system(size: 46, weight: .semibold, design: .rounded).monospacedDigit())
                Text(snapshot?.subtitle ?? "Waiting for refresh")
                    .foregroundStyle(.secondary)

                HStack {
                    GlyphMetricCard(
                        title: "UTC Offset",
                        value: formattedOffset,
                        systemImage: "globe"
                    )
                    GlyphMetricCard(
                        title: "Format",
                        value: snapshot?.metadata["format"] ?? "24-hour",
                        systemImage: "textformat.123"
                    )
                }
            }
        }
    }

    private var formattedOffset: String {
        guard let offset = snapshot?.metrics["offset"] else {
            return "--"
        }
        return String(format: "UTC%+.0f", offset)
    }
}
