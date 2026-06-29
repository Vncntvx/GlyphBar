import Foundation

/// Structured diagnostic context for observability. Every Command→Job→Effect→Snapshot
/// chain gets a unique correlation ID that flows through the entire pipeline.
struct DiagnosticContext: Sendable {
    let correlationID: String
    let moduleInstanceID: String
    let commandID: String
    let jobID: String?
    let snapshotRevision: Int?
    let effectID: String?
    let packageVersion: String?
    let runtimeGeneration: UInt64?

    static func new(moduleID: ModuleInstanceID) -> DiagnosticContext {
        DiagnosticContext(
            correlationID: UUID().uuidString,
            moduleInstanceID: moduleID.value,
            commandID: UUID().uuidString,
            jobID: nil,
            snapshotRevision: nil,
            effectID: nil,
            packageVersion: nil,
            runtimeGeneration: nil
        )
    }
}
