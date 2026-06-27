import Foundation
import OSLog

final class GlyphLogger {
    let subsystem = "com.wenjiexu.GlyphBar"

    private lazy var general = Logger(subsystem: subsystem, category: "general")
    private lazy var runtime = Logger(subsystem: subsystem, category: "runtime")
    private lazy var routing = Logger(subsystem: subsystem, category: "routing")

    func info(_ message: String) {
        general.info("\(message, privacy: .public)")
    }

    func runtime(_ message: String) {
        runtime.info("\(message, privacy: .public)")
    }

    func warning(_ message: String) {
        general.warning("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        general.error("\(message, privacy: .public)")
    }

    func route(_ message: String) {
        routing.notice("\(message, privacy: .public)")
    }
}
