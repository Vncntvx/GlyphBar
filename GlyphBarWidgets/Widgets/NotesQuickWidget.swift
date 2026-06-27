import SwiftUI
import WidgetKit

struct NotesQuickWidget: Widget {
    let kind = "GlyphBarNotesQuickWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: ModuleTimelineProvider(moduleID: "notesQuick", title: "Notes Quick", symbol: "note.text")
        ) { entry in
            ModuleWidgetView(entry: entry)
        }
        .configurationDisplayName("Notes Quick")
        .description("Shows pinned and recent cached notes.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
