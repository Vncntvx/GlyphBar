import Foundation
import WidgetKit

struct ModuleWidgetEntry: TimelineEntry {
    let date: Date
    let moduleID: String
    let snapshot: WidgetModuleSnapshot
}

struct ModuleTimelineProvider: TimelineProvider {
    let moduleID: String
    let title: String
    let symbol: String
    let bridge: WidgetDataBridge

    init(moduleID: String, title: String, symbol: String, bridge: WidgetDataBridge = WidgetDataBridge()) {
        self.moduleID = moduleID
        self.title = title
        self.symbol = symbol
        self.bridge = bridge
    }

    func placeholder(in context: Context) -> ModuleWidgetEntry {
        ModuleWidgetEntry(
            date: Date(),
            moduleID: moduleID,
            snapshot: WidgetDataBridge.unavailableSnapshot(moduleID: moduleID, title: title, symbol: symbol)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ModuleWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ModuleWidgetEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func entry() -> ModuleWidgetEntry {
        ModuleWidgetEntry(
            date: Date(),
            moduleID: moduleID,
            snapshot: bridge.read(moduleID: moduleID) ?? WidgetDataBridge.unavailableSnapshot(
                moduleID: moduleID,
                title: title,
                symbol: symbol
            )
        )
    }
}
