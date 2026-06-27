import SwiftUI
import WidgetKit

@main
struct GlyphBarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ClockWidget()
        SystemPulseWidget()
        NotesQuickWidget()
        CounterWidget()
        NetworkMockWidget()
    }
}
