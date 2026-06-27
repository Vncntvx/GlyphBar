import SwiftUI
import WidgetKit

struct NetworkMockWidget: Widget {
    let kind = "GlyphBarNetworkMockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: ModuleTimelineProvider(moduleID: "networkMock", title: "Network Mock", symbol: "antenna.radiowaves.left.and.right")
        ) { entry in
            ModuleWidgetView(entry: entry)
        }
        .configurationDisplayName("Network Mock")
        .description("Shows the cached async network mock state.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
