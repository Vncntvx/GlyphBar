import Foundation

/// Per-module logging facade. Modules receive a tagged logger instead of using
/// the global `GlyphLogger` directly.
@MainActor
final class LoggingCapability: Capability {
    static let declaredKey: CapabilityKey = .logging

    private let moduleID: String
    private let logger: GlyphLogger

    init(moduleID: String, logger: GlyphLogger) {
        self.moduleID = moduleID
        self.logger = logger
    }

    func info(_ message: String) {
        logger.info("[\(moduleID)] \(message)")
    }

    func warn(_ message: String) {
        logger.warning("[\(moduleID)] \(message)")
    }

    func error(_ message: String) {
        logger.error("[\(moduleID)] \(message)")
    }

    func debug(_ message: String) {
        logger.runtime("[\(moduleID)] \(message)")
    }
}
