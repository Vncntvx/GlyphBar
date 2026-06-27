import SwiftUI
import WidgetKit

struct ClockWidget: Widget {
    let kind = "GlyphBarClockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: ModuleTimelineProvider(moduleID: "clock", title: "Clock", symbol: "clock")
        ) { entry in
            ModuleWidgetView(entry: entry)
        }
        .configurationDisplayName("Clock")
        .description("Shows the cached GlyphBar clock snapshot.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
