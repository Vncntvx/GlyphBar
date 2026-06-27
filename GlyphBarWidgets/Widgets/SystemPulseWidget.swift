import SwiftUI
import WidgetKit

struct SystemPulseWidget: Widget {
    let kind = "GlyphBarSystemPulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: ModuleTimelineProvider(moduleID: "systemPulse", title: "System Pulse", symbol: "waveform.path.ecg")
        ) { entry in
            ModuleWidgetView(entry: entry)
        }
        .configurationDisplayName("System Pulse")
        .description("Shows cached CPU, memory, and storage indicators.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
