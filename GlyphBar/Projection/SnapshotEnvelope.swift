import Foundation

/// The versioned envelope the kernel publishes for a module snapshot. Carries
/// the module's `ProjectionSet` plus metadata (health, TTL, freshness) needed
/// by the presentation layer.
///
/// - `id`: module ID in P1, upgraded to `ModuleInstanceID` in P3.
/// - `schemaVersion`: bumped when `ProjectionSet` shape changes; consumers
///   must reject envelopes with a higher schema than they understand.
struct SnapshotEnvelope: Sendable, Identifiable {
    let id: String
    let schemaVersion: Int
    let capturedAt: Date
    let validUntil: Date?
    let freshness: SnapshotFreshness
    let health: ModuleHealth
    let projections: ProjectionSet

    init(
        id: String,
        schemaVersion: Int = 1,
        capturedAt: Date = Date(),
        validUntil: Date? = nil,
        freshness: SnapshotFreshness = .fresh,
        health: ModuleHealth = .healthy,
        projections: ProjectionSet
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.validUntil = validUntil
        self.freshness = freshness
        self.health = health
        self.projections = projections
    }
}
