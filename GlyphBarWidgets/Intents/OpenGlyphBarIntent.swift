import AppIntents
import Foundation

/// Intent to open the GlyphBar app from Widgets, Shortcuts, or Siri.
///
/// On macOS 27+ the intent declares `IntentAuthenticationPolicy` for
/// biometric-protected actions and `supportedModes` for foreground/background
/// execution control (replacing the deprecated `openAppWhenRun`).
struct OpenGlyphBarIntent: AppIntent {
    static var title: LocalizedStringResource = "Open GlyphBar"

    @available(macOS 26.0, iOS 26.0, watchOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    static var authenticationPolicy: IntentAuthenticationPolicy {
        .alwaysAllowed
    }

    @Parameter(
        title: "Module",
        description: "The module to open in GlyphBar.",
        default: ""
    )
    var moduleID: String

    init() {
        moduleID = ""
    }

    init(moduleID: String) {
        self.moduleID = moduleID
    }

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(Self.url(moduleID: moduleID)))
    }

    static func url(moduleID: String) -> URL {
        let trimmed = moduleID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return URL(string: "glyphbar://app/panel")!
        }
        return URL(string: "glyphbar://module/\(trimmed)")!
    }
}

/// Refreshes all enabled modules in GlyphBar.
///
/// Available on macOS 27+ where App Intents gain `IntentAuthenticationPolicy`
/// for declaring the security requirements of each intent.
@available(macOS 27.0, *)
struct RefreshAllModulesIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh All Modules"

    static var description: IntentDescription {
        IntentDescription(
            "Refreshes all enabled modules in GlyphBar to fetch the latest data.",
            categoryName: "GlyphBar"
        )
    }

    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    static var authenticationPolicy: IntentAuthenticationPolicy {
        .alwaysAllowed
    }

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(URL(string: "glyphbar://app/refresh")!))
    }
}

/// Opens a specific module in GlyphBar's quick panel.
///
/// Useful for Siri shortcuts: "Show clock in GlyphBar".
struct OpenModuleIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Module"

    static var description: IntentDescription {
        IntentDescription(
            "Opens a specific module's panel in GlyphBar.",
            categoryName: "GlyphBar"
        )
    }

    @available(macOS 26.0, iOS 26.0, watchOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @Parameter(
        title: "Module",
        description: "The module to show (e.g., clock, counter, networkMock)."
    )
    var moduleID: String

    init() {
        moduleID = ""
    }

    init(moduleID: String) {
        self.moduleID = moduleID
    }

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(OpenGlyphBarIntent.url(moduleID: moduleID)))
    }
}
