import AppIntents
import Foundation

struct OpenGlyphBarIntent: AppIntent {
    static var title: LocalizedStringResource = "Open GlyphBar"

    @Parameter(title: "Module ID")
    var moduleID: String

    init() {
        moduleID = ""
    }

    init(moduleID: String) {
        self.moduleID = moduleID
    }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
