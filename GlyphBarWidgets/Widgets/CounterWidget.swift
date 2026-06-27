import SwiftUI
import WidgetKit

struct CounterWidget: Widget {
    let kind = "GlyphBarCounterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: ModuleTimelineProvider(moduleID: "counter", title: "Counter", symbol: "number.circle")
        ) { entry in
            ModuleWidgetView(entry: entry)
        }
        .configurationDisplayName("Counter")
        .description("Shows the cached counter value.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
