import Foundation
import OSLog

struct LogEntry: Hashable, Identifiable {
    let id = UUID()
    let date: Date
    let category: String
    let level: String
    let message: String
}

final class GlyphLogger {
    let subsystem = "com.wenjiexu.GlyphBar"

    private static let bufferLimit = 500
    private let bufferQueue = DispatchQueue(label: "com.wenjiexu.GlyphBar.logger.buffer")
    private var buffer: [LogEntry] = []

    private lazy var general = Logger(subsystem: subsystem, category: "general")
    private lazy var runtime = Logger(subsystem: subsystem, category: "runtime")
    private lazy var routing = Logger(subsystem: subsystem, category: "routing")
    private lazy var statusItem = Logger(subsystem: subsystem, category: "statusItem")

    /// Snapshot of recent in-session log entries (newest last), capped at 500.
    func recentEntries() -> [LogEntry] {
        bufferQueue.sync { buffer }
    }

    private func record(_ category: String, level: String, message: String) {
        bufferQueue.sync {
            buffer.append(LogEntry(date: Date(), category: category, level: level, message: message))
            if buffer.count > Self.bufferLimit {
                buffer.removeFirst(buffer.count - Self.bufferLimit)
            }
        }
    }

    func info(_ message: String) {
        general.info("\(message, privacy: .public)")
        record("general", level: "info", message: message)
    }

    func runtime(_ message: String) {
        runtime.info("\(message, privacy: .public)")
        record("runtime", level: "info", message: message)
    }

    func warning(_ message: String) {
        general.warning("\(message, privacy: .public)")
        record("general", level: "warning", message: message)
    }

    func error(_ message: String) {
        general.error("\(message, privacy: .public)")
        record("general", level: "error", message: message)
    }

    func route(_ message: String) {
        routing.notice("\(message, privacy: .public)")
        record("routing", level: "notice", message: message)
    }

    /// Status item lifecycle / interaction diagnostics.
    func statusItem(_ message: String) {
        statusItem.notice("\(message, privacy: .public)")
        record("statusItem", level: "notice", message: message)
    }
}
