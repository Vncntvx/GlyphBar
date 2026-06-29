import Foundation

/// Public API for external data ingestion (CLI, Shortcuts, CI, URL schemes).
/// Third-party modules can publish snapshots, invalidate data, or clear
/// their instance state through this API.
@MainActor
final class IngestionAPI {
    private var subscribers: [@Sendable (IngestionEvent) -> Void] = []
    private let logger: GlyphLogger

    init(logger: GlyphLogger = GlyphLogger()) {
        self.logger = logger
    }

    /// Publish a snapshot payload for a module instance.
    /// Validates the schema version before accepting.
    func publish(payload: IngestionPayload, forInstance id: ModuleInstanceID) throws {
        guard payload.schemaVersion == ProtocolVersions.current.snapshotSchema else {
            throw IngestionError.unsupportedSchemaVersion(payload.schemaVersion)
        }
        logger.info("Ingestion: publish for \(id.value)")
        notify(.snapshotPublished(instanceID: id, payload: payload))
    }

    /// Invalidate the current snapshot for a module instance.
    func invalidate(instance id: ModuleInstanceID) throws {
        logger.info("Ingestion: invalidate \(id.value)")
        notify(.snapshotInvalidated(instanceID: id))
    }

    /// Clear all data for a module instance.
    func clear(instance id: ModuleInstanceID) throws {
        logger.info("Ingestion: clear \(id.value)")
        notify(.instanceCleared(instanceID: id))
    }

    /// Subscribe to ingestion events. Internally converted to Commands.
    func subscribe(_ handler: @escaping @Sendable (IngestionEvent) -> Void) {
        subscribers.append(handler)
    }

    private func notify(_ event: IngestionEvent) {
        for handler in subscribers {
            handler(event)
        }
    }
}

struct IngestionPayload: Codable, Sendable {
    let schemaVersion: Int
    let snapshot: ExternalSnapshotV2
    let signals: [ExternalSignal]?
    let source: IngestionSource
    let emittedAt: Date

    init(
        schemaVersion: Int = ProtocolVersions.current.snapshotSchema,
        snapshot: ExternalSnapshotV2,
        signals: [ExternalSignal]? = nil,
        source: IngestionSource,
        emittedAt: Date = .now
    ) {
        self.schemaVersion = schemaVersion
        self.snapshot = snapshot
        self.signals = signals
        self.source = source
        self.emittedAt = emittedAt
    }
}

/// Simplified snapshot model for external ingestion.
struct ExternalSnapshotV2: Codable, Sendable {
    let title: String
    let subtitle: String
    let systemImage: String
    let metrics: [String: Double]?
    let notes: [String]?
}

struct ExternalSignal: Codable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    let severity: String
}

enum IngestionSource: String, Sendable, Codable {
    case cli
    case shortcuts
    case ci
    case urlScheme
    case internal_
}

enum IngestionEndpoint: Sendable {
    case urlScheme(String)
    case xpcService(String)
}

enum IngestionEvent: Sendable {
    case snapshotPublished(instanceID: ModuleInstanceID, payload: IngestionPayload)
    case snapshotInvalidated(instanceID: ModuleInstanceID)
    case instanceCleared(instanceID: ModuleInstanceID)
}

enum IngestionError: Error, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case unknownInstance(String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let v): return "Unsupported schema version: \(v)"
        case .unknownInstance(let id): return "Unknown instance: \(id)"
        case .invalidPayload(let msg): return "Invalid payload: \(msg)"
        }
    }
}
