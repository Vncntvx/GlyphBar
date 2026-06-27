import Foundation

enum AppGroup {
    static let identifier = "group.com.wenjiexu.GlyphBar"

    static func defaults(preferredSuiteName: String? = identifier) -> UserDefaults {
        if let preferredSuiteName,
           let suite = UserDefaults(suiteName: preferredSuiteName) {
            return suite
        }

        return .standard
    }
}
